#!/usr/bin/env bash
#set -x

restore_terminal(){
	printf "\x1B[?25h"
}

trap restore_terminal EXIT INT TERM

work_dir="${YTDLPS_WORK_DIR:-.yt-dlps-work}"

check_dependencies(){
	local missing_deps=()
	local dep

	if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
		echo "Error: Bash 4.3 or newer is required." >&2
		echo "Current version: $BASH_VERSION" >&2
		exit 1
	fi

	for dep in jq yt-dlp ffmpeg ffprobe tput firefox; do
		if ! command -v "$dep" > /dev/null 2>&1; then
			missing_deps+=("$dep")
		fi
	done

	if (( ${#missing_deps[@]} > 0 )); then
		echo "Error: missing required dependencies: ${missing_deps[*]}" >&2
		echo "Install them and make sure they are available in PATH before running yt-dlps.sh." >&2
		exit 1
	fi
}

validate_num_vids_json(){
	local json_path=$1

	jq -e '
		type == "object"
		and length > 0
		and all(.[]; test("^[0-9]+$") and tonumber >= 0)
	' "$json_path" > /dev/null 2>&1
}

json2arr(){
	# Takes a json relative path and outputs its content into
	# an associative array given as a name in the second input
	local json_path=$1
	local -n output_arr=$2

        # Clear previous contents
        output_arr=()

        # Read list genres and urls from json into a temporary file
        jq -r 'keys_unsorted[]' "$json_path" > "$work_dir/tmplists.txt"
        jq -r 'values[]' "$json_path" > "$work_dir/tmpurls.txt"

        # Create array from tmp file
        mapfile -t genres < "$work_dir/tmplists.txt"
        mapfile -t urls < "$work_dir/tmpurls.txt"

        rm "$work_dir/tmplists.txt"
        rm "$work_dir/tmpurls.txt"

        # Write data into array
        for ((index=0; index<"${#genres[@]}"; index++)); do
                output_arr["${genres[index]}"]="${urls[index]}"
		if [[ "$verbose" = "True" ]]; then
			echo "${genres[index]}"
			echo "${urls[index]}"
		fi
        done
}

color_str(){
	# Takes a string given on its 2nd arg and colors it according 
	# to the 3rd arg, colored string is returned on its 1st nameref arg 
	
	local -n return_string=$1
	local input_string=$2
	local color=$3

	color_green="\x1B[32m"
	color_blue="\x1B[34m"
	color_red="\x1B[31m"
	color_reset="\x1B[0m"

	case "$color" in
	*"green"*)
		return_string=$color_green$input_string$color_reset
	;;
	*"red"*)
		return_string=$color_red$input_string$color_reset
	;;	
	*"blue"*)
		return_string=$color_blue$input_string$color_reset
	;;	
	esac
}

print_bar(){
	local current_song=$1
	local list_songs=$2
	local genre=$3
	local max_genre_len=$4
	local bar_type=$5

	# Variables for customizing terminal output
	local fill_char="■"
	local empty_char="▨"
	local skipped_playlist_empty_char="·"
	local skipped_str="Nothing to download since previous execution"
	local fill_char_colored

	# Get length of loading bar
	local bar_str=()
	local columns=$(tput cols)
	local list_str_len=${#list_songs}

	# Pad string on first column so that data is alligned
	local genre_str_len=${#genre}
	local pad_len=$(( $max_genre_len - $genre_str_len ))
	local index=0
	for ((index=0; index<"$pad_len"; index++)); do
		genre+=" "
	done

	# Compute percentage of completion for playlist
	local perc_done=$((100*$current_song/$list_songs))

	# Pad string for song fraction column
	frac_done_str="($current_song/$list_songs)"
	frac_done_str_len=${#frac_done_str}
	local -i max_frac_len=11
	local -i pad_len=$(( $max_frac_len - $frac_done_str_len ))
	local pad=""
	for ((index=0; index<"$pad_len"; index++)); do
		pad+=" "
	done
	frac_done_str=$pad$frac_done_str

	# Pad string for download completion column
	perc_done_str="$perc_done%"
	perc_done_str_len=${#perc_done_str}
	local -i max_perc_len=6
	pad_len=$(( $max_perc_len - $perc_done_str_len ))
	pad=""
	for ((index=0; index<"$pad_len"; index++)); do
		pad+=" "
	done
	perc_done_str=$pad$perc_done_str

	# Combine columns on both sides to adjust length of loading bar
	local right_bar_str="$frac_done_str$perc_done_str"	
	local left_bar_str="$genre "	
	local right_bar_str_len="${#right_bar_str}"	
	local left_bar_str_len="${#left_bar_str}"	

	# Terminal width minus length of text to it's right and left plus cheeky magic num 
	local bar_len=$(( $columns - $right_bar_str_len - $left_bar_str_len - 1 ))

	# If we need to draw a skipped playlist bar we exit early
	if [[ $bar_type == "skipped_playlist" ]]; then
		
		# Pad loading bar	
		local len_skipped_str=${#skipped_str}
		local side_padding
		local -i side_padding_len=$(( ($bar_len - $len_skipped_str) / 2 ))
		for ((index=0; index<$side_padding_len; index++)); do
			side_padding+="$skipped_playlist_empty_char"
		done

		# Color bar before printing
		bar_str="$side_padding$skipped_str$side_padding"
		color_str "bar_str" "$bar_str" "blue"
		echo -ne "$left_bar_str$bar_str$right_bar_str\r"

		return
	fi

	# If we need to increment the bar for a skipped song
	case "$bar_type" in
	 *"skipped_song"*) 
		color_str "fill_char_colored" "$fill_char" "blue"
		
	;;	
	 *"downloaded_song"*) 
		color_str "fill_char_colored" "$fill_char" "green"

	esac

	# Fill loading bar
	for (( index=0; index<="$bar_len"; index++)); do
		if ((index < $bar_len*$perc_done/100)); then
			bar_str+="$fill_char_colored"
		else
			bar_str+="$empty_char"
		fi
	done

	echo -ne "$left_bar_str$bar_str$right_bar_str\r"
}

parser(){
	# Take a specific string and parse two words out of it at
	# positions given by input. It returns both words on a string

	local string="$1"
	local word_1="$2"
	local word_2="$3"
	local -n words_1_2_arr="$4"
	words_1_2_arr=()

	# Read each word into a string separating by whitespaces
	read -r -a words_arr <<< "${string}" 
	words_1_2_arr[0]="${words_arr[$word_1]}"
	words_1_2_arr[1]="${words_arr[$word_2]}"
	
}

main(){
	# Capture other scripts stdout and parse it
	local downloading_str="[download] Downloading item "
	local skipped_song_str="has already been recorded in the archive"
	local new_playlist_str="[download] Downloading playlist: "
	local skipped_playlist_str="Skipping the following list:"
	local parsed_data=()
	local parsed_playlist=()
	declare -A num_lists_arr
	local verbose=$1
	local first_execution="False"
	local playlist_index=0
	declare -a genres_list
	local list_str_len=0
	local max_str_len=0
	local song_num=0

	mkdir -p "$work_dir"

	# Draw first frame of CLI
	
	# Hide cursor
	printf "\x1B[?25l"
	
	# Get info for amount of media to download for initial frame
	if ! validate_num_vids_json "$work_dir/num_vids.json"; then
		first_execution="True"
		rm -f "$work_dir/num_vids.json"
		if ! bash ./Utils/build_num_vids.sh "$work_dir/num_vids.json"; then
			echo "Error: could not build $work_dir/num_vids.json." >&2
			exit 1
		fi
	fi

	if ! validate_num_vids_json "$work_dir/num_vids.json"; then
		echo "Error: $work_dir/num_vids.json is missing playlist counts or contains invalid values." >&2
		exit 1
	fi

	# TODO: Constructing the first frame from num_vids means that we erroneosly
	# report the amount of tracks to download until it's the turn to download
	# that playlist.
	json2arr "$work_dir/num_vids.json" "num_lists_arr"	

	# Get genres input by user into an indexed array to update bars later
	genres_list=("${!num_lists_arr[@]}")

	# Get maximum str length of genres to pass to print_bar and line them up nice
	for genre_str in "${!num_lists_arr[@]}"; do 
		list_str_len=${#genre_str}
		if [[ $list_str_len -ge $max_str_len ]]; then
			max_str_len=$list_str_len
		fi
	done

	# Iterate through genres creating empty loading bars
	cursor_line=0
	echo "Downloading Playlists"
	((cursor_line++))
	local genre 
	for genre in "${!num_lists_arr[@]}"; do
		if [[ "${num_lists_arr[$genre]}" = "0" ]]; then
			print_bar "1" "1" "$genre" "$max_str_len" "skipped_playlist"
		else
			print_bar "0" "${num_lists_arr[$genre]}" "$genre" "$max_str_len" "False"
		fi
		printf "\n"
		((cursor_line++))	
	done

	# Return to the first line
	printf "\x1B[${cursor_line}A"	
	cursor_line=0

	# Run the download and pipe it's stdout and stderr to the read command
	bash ./Utils/downloader.sh "$first_execution" "$verbose" 2>&1 |

	# Read one line from standard input while treating \ as a character 
	while read -r output; do
		
		if [[ "$verbose" = "True" ]]; then
			echo "$output"
			#echo
		fi
		
		#Parse output line
		case "$output" in
		 *"$downloading_str"*) 

			# Parse data from captured output and update loading bar
			parser "$output" 3 5 "parsed_data"
			current_song="${parsed_data[0]}"
			list_songs="${parsed_data[1]}"
			print_bar \
				"$current_song" \
				"$list_songs" \
				"$genre" \
				"$max_str_len" \
				"downloaded_song"

			((song_num++))
		;;	
		*"$new_playlist_str"*)
			
			genre="${genres_list["$playlist_index"]}"
			((playlist_index++))
			
			# Move cursor down by one line to prepare for bar printing
			printf "\x1B[1B"
			((cursor_line++))
			
			# We start tallying up songs and skipped songs again
			song_num=0
			
		;;
		*"$skipped_playlist_str"*)

			((playlist_index++))	
			
			# Move cursor down by one line to prepare for bar printing
			printf "\x1B[1B"
			((cursor_line++))
			
			# Get skipped genre from captured output
			parser "$output" 4 0 "parsed_genre"
			skipped_genre="${parsed_genre[0]}"
			print_bar \
				"1" \
				"1" \
				"$skipped_genre" \
				"$max_str_len" \
				"skipped_playlist"

			song_num=0
		#;;
		#*"$skipped_song_str"*)
			
			# Get skipped genre from captured output
			#parser "$output" 4 0 "parsed_genre"
			#skipped_genre="${parsed_genre[0]}"

			#((song_num++))
			#print_bar \
				#"$song_num" \
				#"10" \
				#"$genre" \
				#"$max_str_len" \
				#"skipped_song"
		esac
	done
	
	# Show cursor
	printf "\n"	
	printf "\x1B[?25h"

	#echo "Finished downloading playlists"

	# Remove temporary files and update lists
	if [[ "$first_execution" = False ]]; then
		mv "$work_dir/num_vids_current.json" "$work_dir/num_vids.json"
		rm "$work_dir/num_vids_pruned.json" "$work_dir/lists_info_pruned.json"
	fi
}

verbose=$1
if [[ -z $1 ]]; then
	verbose="False"
fi
check_dependencies
main "$verbose"

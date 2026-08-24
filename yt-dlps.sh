#!/usr/bin/env bash
#set -x

json2arr(){
	# Takes a json relative path and outputs its content into
	# an associative array given as a name in the second input
	local json_path=$1
	local -n output_arr=$2

        # Clear previous contents
        output_arr=()

        # Read list genres and urls from json into a temporary file
        jq -r 'keys_unsorted[]' "$json_path" > Utils/tmplists.txt
        jq -r 'values[]' "$json_path" > Utils/tmpurls.txt

        # Create array from tmp file
        mapfile -t genres < Utils/tmplists.txt
        mapfile -t urls < Utils/tmpurls.txt

        rm Utils/tmplists.txt
        rm Utils/tmpurls.txt

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
	# Takes a string on given on its 2nd arg and colors it according 
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
	local skipped_playlist=$5

	# Variables for customizing terminal output
	local fill_char="■"
	local empty_char="▨"
	local skipped_playlist_empty_char="·"
	local skipped_str="Nothing to download since previous execution"

	# Colorize variables
	local fill_char_downloaded
	color_str "fill_char_downloaded" "$fill_char" "green"

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
	if [[ $skipped_playlist == "True" ]]; then
		
		# Pad loading bar	
		local len_skipped_str=${#skipped_str}
		local side_padding
		local -i side_padding_len=$(( ($bar_len - $len_skipped_str) / 2 ))
		for ((index=0; index<=$side_padding_len; index++)); do
			side_padding+="$skipped_playlist_empty_char"
		done

		# Color bar before printing
		bar_str="$side_padding$skipped_str$side_padding"
		color_str "bar_str" "$bar_str" "blue"
		echo -ne "$left_bar_str$bar_str$right_bar_str\r"

		return
	fi

	# Fill loading bar
	for ((index=0; index<="$bar_len"; index++)); do
		if ((index < $bar_len*$perc_done/100)); then
			bar_str+="$fill_char_downloaded"
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
	local downloaded_str="has already been recorded in the archive"
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

	# Draw first frame of CLI
	
	# Hide cursor
	printf "\x1B[?25l"
	
	# Get info for amount of media to download for initial frame
	if ! [[ -e Utils/num_vids.json ]]; then
		first_execution="True"
		./Utils/build_num_vids.sh "Utils/num_vids.json" > /dev/null 2>&1 
	fi

	# TODO: Constructing the first frame from num_vids means that we erroneosly
	# report the amount of tracks to download until it's the turn to download
	# that playlist.
	json2arr "Utils/num_vids.json" "num_lists_arr"	

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
		print_bar "0" "${num_lists_arr[$genre]}" "$genre" "$max_str_len" "False"
		printf "\n"
		((cursor_line++))	
	done

	# Return to the first line
	printf "\x1B[${cursor_line}A"	
	cursor_line=0

	# Run the download and pipe it's stdout and stderr to the read command
	./Utils/downloader.sh "$first_execution" "$verbose" 2>&1 |

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
				"False"
		;;	
		*"$downloaded_str"*)

			parser "$output" 3 5 "parsed_data"
			current_song="${parsed_data[0]}"
			list_songs="${parsed_data[1]}"
			# ¿Color bar differently when skipped track? 
		;;
		*"Nothing to download"*)
			#echo "$output"
		;;
		*"$new_playlist_str"*)
			
			genre="${genres_list["$playlist_index"]}"
			((playlist_index++))
			
			# Move cursor down by one line to prepare for bar printing
			printf "\x1B[1B"
			((cursor_line++))
			#echo "$output" 
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
				"True"
			#echo -ne "$skipped_genre: Skipped playlist. No new songs to download\r"
		esac
	done
	
	# Show cursor
	printf "\n"	
	printf "\x1B[?25h"

	#echo "Finished downloading playlists"

	# Remove temporary files and update lists
	if [[ "$first_execution" = False ]]; then
		mv Utils/num_vids_current.json Utils/num_vids.json
		rm Utils/num_vids_pruned.json Utils/lists_info_pruned.json
	fi
}

verbose=$1
if [[ -z $1 ]]; then
	verbose="False"
fi
main "$verbose"

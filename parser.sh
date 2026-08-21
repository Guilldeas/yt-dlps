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


print_bar(){
	local current_song=$1
	local list_songs=$2
	local genre=$3
	local max_genre_len=$4

	local perc_done=$((100*$current_song/$list_songs))

	local fill_char="■"
	local empty_char="▨"
	local bar_str=()

	# Get length of loading bar
	local columns=$(tput cols)
	local list_str_len=${#list_songs}

	# Pad genre so that loading bars are alligned
	local genre_str_len=${#genre}
	local pad_len=$(($max_genre_len-$genre_str_len))
	for ((index=0; index<"$pad_len"; index++)); do
		genre+=" "
	done
	# terminal width minus length of genre, chars and max len of ratio
	local bar_len=$(($columns-$max_genre_len-2*$list_str_len-11))

	# Fill loading bar
	local index
	for ((index=0; index<="$bar_len"; index++)); do
		if ((index < $bar_len*$perc_done/100)); then
			bar_str+="$fill_char"
		else
			bar_str+="$empty_char"
		fi
	done

	echo -ne "$genre $bar_str ($current_song/$list_songs) $perc_done%\r"
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
	local parsed_data=()
	local parsed_playlist=()
	declare songnum=0
	declare -A num_lists_arr
	local verbose="True"
	local first_execution="False"
	local playlist_index=0
	declare -a genres_list
	local list_str_len=0
	local max_str_len=0

	# Draw first frame of CLI
	
	# Hide cursor
	#printf "\x1B[?25l"
	
	# Get info for amount of media to download for initial frame
	if ! [[ -e Utils/num_vids.json ]]; then
		first_execution="True"
		./Utils/build_num_vids.sh "Utils/num_vids.json" > /dev/null 2>&1 
	fi
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
		print_bar "0" "${num_lists_arr[$genre]}" "$genre" "$max_str_len"
		printf "\n"
		((cursor_line++))	
	done

	# Return to the first line
	printf "\x1B[${cursor_line}A"	
	cursor_line=0

	

	# Run the download and pipe it's stdout and stderr to the read command
	./Utils/downloader.sh "$first_execution" 2>&1 |

	# Read one line from standard input while treating \ as a character 
	while read -r output; do
		
		if [[ "$verbose" = "True" ]]; then
			echo "$output"
			#echo
		fi
		
		#Parse output line
		case "$output" in
		 *"$downloading_str"*) 
			parser "$output" 3 5 "parsed_data"
			current_song="${parsed_data[0]}"
			list_songs="${parsed_data[1]}"
			print_bar \
				"$current_song" \
				"$list_songs" \
				"$genre" \
				"$max_str_len"
		;;	
		*"$downloaded_str"*)
			((songnum+=1))
			parser "$output" 3 5 "parsed_data"
			current_song="${parsed_data[0]}"
			list_songs="${parsed_data[1]}"
			#echo "already downloaded song" 
		;;
		*"Nothing to download"*)
			#echo "$output"
		;;
		*"$new_playlist_str"*)
			
			# THIS ITERATING BREAKS WHEN WE PRUNE PLAYLISTS
			genre="${genres_list["$playlist_index"]}"
			((playlist_index++))
			songnum=0
			
			# Move cursor down by one line to prepare for bar printing
			printf "\x1B[1B"
			((cursor_line++))
			#echo "$output" 
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

main

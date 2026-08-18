#!/usr/bin/env bash


#----- Variables -------------------------------------------------------------
declare -A list_info_arr
declare num_songs 
first_execution="False"
pruned_playlists="False"

# Default variable for verbose (controlling debugging echos) is False unless user specifies something else
if [ -z $1  ]; then
	verbose="False"
else
	verbose=$1
fi

#----- Functions -------------------------------------------------------------
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

build_num_vids_json(){
	# Builds json with number of videos in playlist	
	
	local json_path=$1

        # Iterate through associative array of genres and urls
        for genre in "${!list_info_arr[@]}"; do
                url="${list_info_arr[$genre]}"

		# Find number of videos in playlist
		num_vids=$(yt-dlp "$url" -I0 -O playlist:playlist_count)

                # If json doesnt exist create it
                if ! [[ -e "$json_path" ]]; then

                        echo file does not exist

                        # Write one line storing a key value pair
                        jq --null-input \
                                --arg key "$genre" \
                                --arg value "$num_vids" \
                                '{($key): $value}' > "$json_path"

                # If json already exists append line to it
                else
                        echo file exists

                        jq \
                                --arg key "$genre" \
                                --arg value "$num_vids" \
                                '. += {($key): $value}' "$json_path" > Utils/num_vids.tmp \
                                && mv Utils/num_vids.tmp "$json_path" 
                fi
        done
}

build_pruned_json() {
	# Takes two jsons and builds a third one with only the values that changed

	local json1="$1"
	local json2="$2"
	local output="$3"

	jq -n \
		--slurpfile a "$json1" \
		--slurpfile b "$json2" \
		'$b[0] | with_entries(select(.value != $a[0][.key]))' \
		> "$output"
}

populate_pruned_urls_json() {

        local pruned_json="$1"
        local urls_json="$2"
        local output="$3"

        jq -n \
                --slurpfile pruned "$pruned_json" \
                --slurpfile urls "$urls_json" \
                '$pruned[0] | with_entries(.value = $urls[0][.key])' \
                > "$output"

	pruned_playlists="True"	
}

get_config(){
        local index

	# Populate associative array with genres as keys and playlist urls as values
	json2arr "Utils/lists_info_test.json" "list_info_arr"
	
	# Store numbers of videos on each playlist if it wasnt done before
	if ! [[ -e Utils/num_vids.json ]]; then
		echo First execution
		build_num_vids_json "Utils/num_vids.json"	
		first_execution="True"
	fi
	
	# Check whether more videos have been added to playlists
	if [[ "$first_execution" = False ]]; then
		echo Not first execution
		
		# Find how many videos are in playlists
		build_num_vids_json "Utils/num_vids_current.json" 
		
		# Keep only genre, num_videos pairs that have been updated
		build_pruned_json \
			"Utils/num_vids.json" \
			"Utils/num_vids_current.json" \
			"Utils/num_vids_pruned.json"

		# populate pruned list with urls instead of num_vids
		populate_pruned_urls_json\
			"Utils/num_vids_pruned.json" \
			"Utils/lists_info_test.json" \
			"Utils/lists_info_pruned.json"
	fi
	# IM NOT UPDATING THE PREVIOUS AND NEW LIST AT THE END OF CODE EXEC

}


build_folder_struct(){
	# Find whether expected directory structure is present
	for genre in "${!list_info_arr[@]}"; do
		if [[ -d "$genre" ]]; then
        		continue

		# If not then build it
		else
	        	mkdir -p "$genre" \
			&& echo "Created directory $genre"
		fi
	done
}


download_playlists() {
	local genre
	local url

	if [[ "$pruned_playlists" = True ]]; then
		json2arr "Utils/lists_info_pruned.json" "list_info_arr"
		echo "pruned-----------------------"

		# REMOVE LATER TROUBLESHOOTING
		for ((index=0; index<"${#list_info_arr[@]}"; index++)); do
			echo "${list_info_arr[index]}"
		done
	else
		json2arr "Utils/lists_info_test.json" "list_info_arr"
	fi
	
	# If there is nothing to output break out of function
	if (( "${#list_info_arr[@]}" == 0 )); then
		echo "Nothing to download"
		return 1
	fi	

	for genre in "${!list_info_arr[@]}"; do
		url="${list_info_arr[$genre]}"

		# Download 
		yt-dlp \
		--cookies-from-browser firefox \
		-x \
		--audio-format mp3 \
		--add-metadata \
		--embed-thumbnail \
		--convert-thumbnails jpg \
		--parse-metadata "playlist_index:%(track_number)s" \
		-o "$genre/%(playlist_index)03d - %(title)s.%(ext)s" \
		--download-archive "$genre/archive.txt" \
		--fragment-retries infinite \
		--retry-sleep fragment:exp=1:30 \
		--postprocessor-args "-metadata genre=$genre" \
		"$url"
	done
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

downloader(){
	get_config && build_folder_struct && download_playlists 
}


main(){

	# Capture other scripts stdout and parse it
	local downloading_str="[download] Downloading item "
	local downloaded_str="has already been recorded in the archive"
	local new_playlist_str="[download] Downloading playlist: "
	local parsed_data=()
	declare songnum=0

	# Run the download and pipe it's stdout and stderr to the read command
	downloader 2>&1 |

	# Read one line from standard input while treating \ as a character 
	while read -r output; do
		
		if [[ "$verbose" = "True" ]]; then
			echo "$output"
			echo
		fi
		
		#Parse output line
		case "$output" in
		 *"$downloading_str"*) 
			parser "$output" 3 5 "parsed_data"
			current_song="${parsed_data[0]}"
			list_songs="${parsed_data[1]}"
			echo "downloading song number:$current_song/$list_songs" 
		;;	
		*"$downloaded_str"*)
			((songnum+=1))
			parser "$output" 3 5 "parsed_data"
			current_song="${parsed_data[0]}"
			list_songs="${parsed_data[1]}"
			echo "already downloaded song" 
		;;
		*"Nothing to download"*)
			echo "$output"
		;;
		*"$new_playlist_str"*)
			songnum=0
			echo "$output" 
		esac
	done
	
	echo "Finished downloading playlists"

	# Remove temporary files and update lists
	if [[ "$first_execution" = False ]]; then
		mv Utils/num_vids_current.json Utils/num_vids.json
		rm Utils/num_vids_pruned.json Utils/lists_info_pruned.json
	fi
}

# ----- Main code -------------------------------------------------------------
main

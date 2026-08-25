#!/usr/bin/env bash
#set -x


#----- Variables -------------------------------------------------------------
declare -A list_info_arr
declare num_songs 
first_execution=$1
pruned_playlists="False"

# Default variable for verbose (controlling debugging echos) is False unless user specifies something else
if [ -z $2  ]; then
	verbose="False"
else
	verbose=$2
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
	json2arr "Utils/lists_info.json" "list_info_arr"
	
	# Store numbers of videos on each playlist if it wasnt done before
	#if [[ $first_execution = "True"]]; then
		#echo First execution
		#./build_num_vids_json.sh "Utils/num_vids.json"	
		#first_execution="True"
	#fi
	
	# Check whether more videos have been added to playlists
	if [[ "$first_execution" = False ]]; then
		echo Not first execution
		
		# Find how many videos are in playlists
		bash ./Utils/build_num_vids.sh "Utils/num_vids_current.json" 
		
		# Keep only genre, num_videos pairs that have been updated
		build_pruned_json \
			"Utils/num_vids.json" \
			"Utils/num_vids_current.json" \
			"Utils/num_vids_pruned.json"

		# populate pruned list with urls instead of num_vids
		populate_pruned_urls_json\
			"Utils/num_vids_pruned.json" \
			"Utils/lists_info.json" \
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
		json2arr "Utils/lists_info.json" "list_info_arr"
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


yt_dlp_command(){
	local genre=$1
	local url=$2

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
}

download_playlists_v2() {
	local genre
	local url
	declare -A list_info_arr_pruned
	declare -A list_info_arr


	# Get list of pruned keys (genres) if it exists
	if [[ -e "Utils/lists_info_pruned.json" ]]; then
		json2arr "Utils/lists_info_pruned.json" "list_info_arr_pruned"
		genres_list_pruned=("${!list_info_arr_pruned[@]}")
	fi

	# We iterate through the whole set of lists
	json2arr "Utils/lists_info.json" "list_info_arr"

	for genre in "${!list_info_arr[@]}"; do
		url="${list_info_arr[$genre]}"

		# On first execution we simply download
		if ! [[ -e "Utils/lists_info_pruned.json" ]]; then
			yt_dlp_command "$genre" "$url"

		# On further executions we report to the parser whenever 
		# we ignore playlists
		else
			# Check whether this genre was kept (pruned)
			local kept_genre_bool="False"
			for kept_genre_str in "${genres_list_pruned[@]}"; do
				if [[ $genre == $kept_genre_str ]]; then
					kept_genre_bool="True"
				fi
			done

			# Inform the parser we are skipping this list
			# to report on TUI
			if [[ $kept_genre_bool == "False" ]]; then
				echo "Skipping the following list: $genre"
			
			# If the list needs downloading we call the yt command
			else
				yt_dlp_command "$genre" "$url"
			fi
		fi
	done
}


get_config && build_folder_struct && download_playlists_v2

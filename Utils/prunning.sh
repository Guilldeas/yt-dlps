#!/usr/bin/env bash
#set -x

# The plan is this: We want to know when was a list skipped for being prunned
# finding out from parser is kinda hard because we would need to access the 
# lists_info_pruned.json whih is being accessed inside the while loop by a different
# subshell (thread) leading to possible race conditions. Refactoring the code is an
# option and perhaps it's lazy not to go that route but I think it's easier to simply
# iterate all of lists at the download_playlist function and echo when a playlist has 
# been pruned out.

#----- Variables -------------------------------------------------------------
declare -A list_info_arr
declare -A list_info_arr_pruned
declare num_songs 
first_execution=$1
pruned_playlists="True"
verbose="True"

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

download_playlists() {
	local genre
	local url


	# Get list of pruned keys (genres) if it exists
	if [[ -e "Utils/lists_info_pruned.json" ]]; then
		json2arr "Utils/lists_info_pruned.json" "list_info_arr_pruned"
		genres_list_pruned=("${!list_info_arr_pruned[@]}")
	fi

	# We iterate through the whole set of lists
	json2arr "Utils/lists_info_test.json" "list_info_arr"

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
				echo " -------------------- Skipping the following list: $genre"
			
			# If the list needs downloading we call the yt command
			else
				yt_dlp_command "$genre" "$url"
			fi
		fi
	done
}


download_playlists 

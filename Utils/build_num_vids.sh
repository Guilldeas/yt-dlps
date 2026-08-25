#!/usr/bin/env bash
#set -x


# Builds json with number of videos in playlist	

json_path=$1
declare -A list_info_arr


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

json2arr "Utils/lists_info.json" "list_info_arr"

# Iterate through associative array of genres and urls
for genre in "${!list_info_arr[@]}"; do
	url="${list_info_arr[$genre]}"

	# Find number of videos in playlist
	num_vids=$(yt-dlp "$url" -I0 -O playlist:playlist_count)

	# If json doesnt exist create it
	if ! [[ -e "$json_path" ]]; then

		if [[ "$verbose" = "True" ]]; then
			echo file does not exist
		fi

		# Write one line storing a key value pair
		jq --null-input \
			--arg key "$genre" \
			--arg value "$num_vids" \
			'{($key): $value}' > "$json_path"

	# If json already exists append line to it
	else
		if [[ "$verbose" = "True" ]]; then
			echo file exists
		fi

		jq \
			--arg key "$genre" \
			--arg value "$num_vids" \
			'. += {($key): $value}' "$json_path" > Utils/num_vids.tmp \
			&& mv Utils/num_vids.tmp "$json_path" 
	fi
done

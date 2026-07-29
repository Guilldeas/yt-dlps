#!/usr/bin/env bash

#----- Variables
declare -A list_info_arr

#----- Functions
get_config(){
        local index

        # Read list genres and urls from json into a temporary file
        jq -r 'keys[]' Utils/lists_info_test.json > Utils/tmplists.txt
        jq -r 'values[]' Utils/lists_info_test.json > Utils/tmpurls.txt

        # Create array from tmp file
        mapfile -t genres < Utils/tmplists.txt
        mapfile -t urls < Utils/tmpurls.txt

        rm Utils/tmplists.txt
        rm Utils/tmpurls.txt
        
        # Write data into array
        for ((index=0; index<"${#genres[@]}"; index++)); do
                list_info_arr["${genres[index]}"]="${urls[index]}"
        done
}


build_folder_struct(){
	# Find whether expected directory structure is present
	for genre in "${!list_info_arr[@]}"; do
		if [[ -d "Custom_Playlist/$genres" ]]; then
        		continue

		# If not then build it
		else
	        	mkdir -p "Custom_Playlist/$genre" \
			&& echo "Created directory $genre"
		fi
	done
}


download_playlists() {
    local genre
    local url

    for genre in "${!list_info_arr[@]}"; do
        url="${list_info_arr[$genre]}"

        yt-dlp \
            --cookies-from-browser firefox \
            -x \
            --audio-format mp3 \
            --add-metadata \
            --embed-thumbnail \
            --convert-thumbnails jpg \
            --parse-metadata "playlist_index:%(track_number)s" \
            -o "Custom_Playlist/$genre/%(playlist_index)03d - %(title)s.%(ext)s" \
            --fragment-retries infinite \
            --retry-sleep fragment:exp=1:30 \
            --postprocessor-args "-metadata genre=$genre" \
            "$url"
    done
}

# ----- Main code
get_config && build_folder_struct && download_playlists

#!/usr/bin/env bash


#----- Variables -------------------------------------------------------------
declare -A list_info_arr

#----- Functions -------------------------------------------------------------

get_config(){
        local index

        # Read list genres and urls from json into a temporary file
        jq -r 'keys_unsorted[]' Utils/lists_info_test.json > Utils/tmplists.txt
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
            -o "$genre/%(playlist_index)03d - %(title)s.%(ext)s" \
            --download-archive "$genre/archive.txt" \
	    --fragment-retries infinite \
            --retry-sleep fragment:exp=1:30 \
            --postprocessor-args "-metadata genre=$genre" \
            "$url"
    done
}


parser(){
	local string="$1"
	local charnum="$2"
	echo "${string:"$charnum":1}"
}

downloader(){
	get_config && build_folder_struct && download_playlists
}


main(){

	# Capture other scripts stdout and parse it
	local downloading_str="[download] Downloading item "
	local downloaded_str="has already been recorded in the archive"
	local new_playlist_str="[download] Downloading playlist: "

	# Run the download and pipe it's stdout and stderr to the read command
	downloader 2>&1 |

	# Read one line from standard input while treating \ as a character 
	while read -r output; do
		
		#Parse output line
		case "$output" in
		 *"$downloading_str"*) 
			songnum=$(parser "$output" 28)
			echo "downloading song number:$songnum" 
		;;	
		*"$downloaded_str"*)
			((songnum+=1))
			echo "downloading song number:$songnum" 
		;;
		*"$new_playlist_str"*)
			songnum=0
		esac
	done
}

# ----- Main code -------------------------------------------------------------
main

#!/usr/bin/env bash


#----- Variables -------------------------------------------------------------
declare -A list_info_arr
declare num_songs 

#----- Functions -------------------------------------------------------------
json2arr(){
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

check4updates(){
	# Build json with number of videos in playlist	
	
        # Iterate through associative array of genres and urls
        for genre in "${!list_info_arr[@]}"; do
                url="${list_info_arr[$genre]}"

		# Find number of videos in playlist
		num_vids=$(yt-dlp "$url" -I0 -O playlist:playlist_count)

                # If json doesnt exist create it
                if ! [[ -e Utils/num_vids.json ]]; then

                        echo file does not exist

                        # Write one line storing a key value pair
                        jq --null-input \
                                --arg key "$genre" \
                                --arg value "$num_vids" \
                                '{($key): $value}' > Utils/num_vids.json

                # If json already exists append line to it
                else
                        echo file exists

                        jq \
                                --arg key "$genre" \
                                --arg value "$num_vids" \
                                '. += {($key): $value}' Utils/num_vids.json > Utils/num_vids.tmp \
                                && mv Utils/num_vids.tmp Utils/num_vids.json
                fi
        done
}

get_config(){
        local index

	# Populate associative array with genres as keys and playlist urls as values
	json2arr
	
	# TO DO: CHECK WHETHER WE NEED TO DOWNLOAD PLAYLISTS BASED ON NUMBER OF
	# SONGS DOWNLOADED LAST TIME AND SONGS IN PLAYLIST NOW
	# PRUNE ARRAY WITH LIST INFO AND DOWNLOAD
	# UPDATE JSON WITH NUMSONGS	
	check4updates
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


        # Download playlist
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

# Get substring from input 1 of len 1 at chatacter input 2 
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
	# UNCOMMENT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	downloader 2>&1 |

	# Read one line from standard input while treating \ as a character 
	while read -r output; do
		
		#Parse output line
		case "$output" in
		 *"$downloading_str"*) 
			songnum=$(parser "$output" 28)
			echo "downloading song number:$songnum/$num_songs" 
		;;	
		*"$downloaded_str"*)
			((songnum+=1))
			echo "downloading song number:$songnum/$num_songs" 
		;;
		*"$new_playlist_str"*)
			songnum=0
		esac
	done
}

# ----- Main code -------------------------------------------------------------
main 

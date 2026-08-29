#!/usr/bin/env bash
#set -x


# Builds json with number of videos in playlist	

json_path=$1
declare -A list_info_arr
work_dir="${YTDLPS_WORK_DIR:-.yt-dlps-work}"
mkdir -p "$work_dir"
json_dir="${json_path%/*}"
if [[ "$json_dir" != "$json_path" ]]; then
	mkdir -p "$json_dir"
fi


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

json2arr "Utils/lists_info.json" "list_info_arr"

# Iterate through associative array of genres and urls
output_tmp="$work_dir/num_vids.tmp"
jq --null-input "{}" > "$output_tmp" || exit 1

for genre in "${!list_info_arr[@]}"; do
	url="${list_info_arr[$genre]}"

	# Find number of videos in playlist
	if ! num_vids=$(yt-dlp --no-warnings "$url" -I0 -O playlist:playlist_count); then
		echo "Warning: skipping unavailable playlist $genre: $url" >&2
		num_vids=0
	elif ! [[ "$num_vids" =~ ^[0-9]+$ ]]; then
		echo "Warning: skipping playlist with invalid count $genre: $num_vids" >&2
		echo "Playlist URL: $url" >&2
		num_vids=0
	fi

	jq \
		--arg key "$genre" \
		--arg value "$num_vids" \
		". += {(\$key): \$value}" "$output_tmp" > "$output_tmp.next" \
		&& mv "$output_tmp.next" "$output_tmp"
done

mv "$output_tmp" "$json_path"

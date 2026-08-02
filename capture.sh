#!/usr/bin/env bash

# Functions
parser(){
	local string="$1"
	local charnum="$2"
	echo "${string:"$charnum":1}"
}

# Capture other scripts stdout and parse it
downloading_str="[download] Downloading item "
downloaded_str="has already been recorded in the archive"
new_playlist_str="[download] Downloading playlist: "

# Run the script and pipe it's stdout and stderr to the read command
./download_playlists.sh 2>&1 |

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

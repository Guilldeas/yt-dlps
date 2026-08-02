#!/usr/bin/env bash

# Functions
parser(){
	local string="$1"
	echo "${string:28:1}"
}

# Capture other scripts stdout and parse it
pattern_str="[download] Downloading item "

# Run the script and pipe it's stdout and stderr to the read command
./download_playlists.sh 2>&1 |

# Read one line from standard input while treating \ as a character 
while read -r output; do
	
	#Parse output line
	if [[ "$output" == *"$pattern_str"* ]]; then
		echo "downloading song number: $(parser "$output")"	
	else
		continue
	fi
done

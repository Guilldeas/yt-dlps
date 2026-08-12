#!/usr/bin/env bash
set -x
some_key=$1
some_value=$2


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

arr2json(){

        # Iterate through associative array of genres and urls
        for genre in "${!list_info_arr[@]}"; do
                url="${list_info_arr[$genre]}"

                # If json doesnt exist create it
                if ! [[ -e json_test.json ]]; then

                        echo file does not exist

                        # Write one line storing a key value pair
                        jq --null-input \
                                --arg key "$genre" \
                                --arg value "$url" \
                                '{($key): $value}' > json_test.json

                # If json already exists append line to it
                else
                        echo file exists

                        jq \
                                --arg key "$genre" \
                                --arg value "$url" \
                                '. += {($key): $value}' json_test.json > json_test.tmp \
                                && mv json_test.tmp json_test.json
                fi
        done
}

json2arr && arr2json

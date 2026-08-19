#!/usr/bin/env bash
#set -x

print_bar(){
	current_song=$1
	list_songs=$2
	genre=$3

	perc_done=$((100*$current_song/$list_songs))

	fill_char="■"
	empty_char="▩"
	bar_str=()

	# Get length of loading bar
	genre_len=${#genre}
	columns=$(tput cols)
	list_str_len=${#list_songs}

	# terminal width minus length of genre, chars and max len of ratio
	bar_len=$(($columns-$genre_len-2*$list_str_len-11))

	# Fill loading bar
	local index
	for ((index=0; index<="$bar_len"; index++)); do
		if ((index < $bar_len*$perc_done/100)); then
			bar_str+="$fill_char"
		else
			bar_str+="$empty_char"
		fi
	done

	echo -ne "$genre $bar_str ($current_song/$list_songs) $perc_done%\r"
}

for ((i=0; i<=100; i++));do
	print_bar "$i" 100 "This is a long name"
	sleep 0.1
done
echo

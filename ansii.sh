#!/usr/bin/env bash
#set -x

# Hide cursor
printf "\x1B[?25l"

echo This is the first line
echo This is the second line
echo This is the third line
echo This is the fourth line

sleep 3

# Save end of CLI position to return at the end
printf "\x1B 7"

# Move up some lines to the first line printed
line=4
printf "\x1B[${line}A"

# Overwrite that line
#echo -ne "\rOverwrite this line        "
./bar.sh

sleep 2

# Move cursor to the end
printf "\x1B[4E"

# Show cursor
printf "\x1B[?25h"


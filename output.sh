#!/usr/bin/env bash

# Generate some outputs
num_out=5
sec_wait=1
outputs=(foo bar baz)
for output in "${outputs[@]}"; do 
	echo "output is  $output"
	sleep 1
done


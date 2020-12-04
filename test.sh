#!/bin/bash

list=(`cat id.csv|xargs`)
echo "${list[0]}"

list1=(`echo ${list[0]}| tr ',' '\n'`)
echo ${list1[0]}
echo ${list1[1]}
echo ${list1[2]}

array=()

while read line ; do
	echo $line
	array+=($line)
done < id.csv

echo "csv line = ${#array[@]}"

i=0

for e in ${array[@]}; do
	echo "array[$i] = ${e}"
	let i++
done


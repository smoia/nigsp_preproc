#!/usr/bin/env bash

version() {
	echo "Version 0.0.0"
}

# Check input
checkreqvar() {
	reqvar=( "$@" )

	for var in "${reqvar[@]}"
	do
		if [[ -z ${!var+x} ]]
		then
			echo "${var} is unset, exiting program" && exit 1
		else
			echo "${var} is set to ${!var}"
		fi
	done
}

checkoptvar() {
	optvar=( "$@" )

	for var in "${optvar[@]}"
	do
		echo "${var} is set to ${!var}"
	done
}

removeniisfx() {
	echo ${1%.nii*}
}

if_missing_do() {
case $1 in
	mkdir )
		if [ ! -d $2 ]
		then
			echo "Create folder(s)" "${@:2}"
			mkdir -p "${@:2}"
		fi
		;;
	stop )
		if [ ! -e $2 ]
		then
			echo "$2 not found"
			exit 1
		fi
		;;
	* )
		if [ ! -e $3 ]
		then
			printf "%s is missing, " "$3"
			case $1 in
				copy ) echo "copying $2";		cp $2 $3 ;;
				move ) echo "moving $2";		mv $2 $3 ;;
				mask ) echo "binarising $2";	fslmaths $2 -bin $3 ;;
				* ) echo "and you shouldn't see this"; exit ;;
			esac
		fi
		;;
esac
}

replace_and() {
case $1 in
	mkdir) if [ -d $2 ]; then echo "$2 exists already, removing first"; rm -rf $2; fi; mkdir -p "${@:2}" ;;
	touch) if [ -d $2 ]; then echo "$2 exists already, removing first"; rm -rf $2; fi; touch $2 ;;
	* ) echo "This is wrong"; exit ;;
esac
}
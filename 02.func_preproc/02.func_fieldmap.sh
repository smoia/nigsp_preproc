#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fdir"
echo "Optional:"
echo "fmap_str fullmap tmp scriptdir"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
fmap_str=''
fullfmap=none
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
scriptdir=${scriptdir%/*}/..
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-func_in)	func_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-fmap_str)	fmap_str=$2;shift;;
		-fullfmap)	fullfmap=$2;shift;;
		-scriptdir)	scriptdir=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fdir
checkoptvar fmap_str fullfmap tmp scriptdir

### Remove nifti suffix
for var in func_in fullfmap
do
	eval "${var}=${!var%.nii*}"
done

### Name images
sffx=${func_in##*ses-*_}
prfx=${func_in%_$sffx*}
magnitude=${prfx}${fmap_str}_magnitude2
phasediff=${prfx}${fmap_str}_phasediff

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
func=$( basename ${func_in%_*} )

## 01. fieldmap
# If there isn't an estimated field, make it.
if [[ "${fullfmap}" == "none" ]]
then
	echo "Preparing fieldmap"
	if_missing_do stop ${magnitude}.nii.gz
	if_missing_do stop ${magnitude}.json
	if_missing_do stop ${phasediff}.nii.gz

	echo1=$( grep EchoTime1 ${magnitude}.json )
	echo1=${echo1#*: }
	echo1=${echo1%,*}
	echo2=$( grep EchoTime2 ${magnitude}.json )
	echo2=${echo2#*: }
	echo2=${echo2%,*}
	deltaecho=$( echo "(${echo2} - ${echo1}) * 1000" | bc )

	fmap=${func}_fieldmap

	mkdir ${fmap}
	bet ${magnitude} ${magnitude}_brain  -R -f 0.5 -g 0 -n -m

	cd ${fmap}
	echo "Computing fieldmap for ${func}"
	echo "Echo1: ${echo1} s, Echo2: ${echo2} s, Delta: ${deltaecho} ms"
	echo "Echo1: ${echo1} s, Echo2: ${echo2} s, Delta: ${deltaecho} ms" > echo_delta.1D
	fsl_prepare_fieldmap SIEMENS ${phasediff} ${magnitude}_brain fmap_rads ${deltaecho}
	cd ..
	fullfmap=${fmap}/fmap_rads
fi

# 03.2. Applying the warping to the functional volume
echo "Applying Fieldmap to ${func}"
fugue ${func_in} --loadfmap=${fullfmap} --dwell=0.0000029 -u ${tmp}/${func}_fmd

cd ${cwd}
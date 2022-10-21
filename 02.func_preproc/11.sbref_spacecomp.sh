#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sbref_in fdir"
echo "Optional:"
echo "anat adir"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anat=none
adir=none

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sbref_in)	sbref_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-anat)		anat=$2;shift;;
		-adir)		adir=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar sbref_in fdir
checkoptvar anat adir

### Remove nifti suffix
for var in sbref_in anat
do
	eval "${var}=${!var%.nii*}"
done

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
sbref=$( basename ${sbref_in%_*} )

## 01. BET
echo "BETting ${sbref}"
bet ${sbref_in} ${sbref}_brain -R -f 0.5 -g 0 -n -m

## 02. Anat Coreg
if [[ "${anat}" != "none" ]]
then
	if [[ "${adir}" != "none" ]]; then anat=${adir}/${anat}; fi
	if_missing_do stop ${anat}_brain.nii.gz
	echo "Coregistering ${sbref} to ${anat}"
	flirt -in ${anat}_brain -ref ${sbref}_brain -out ../reg/$( basename ${anat} )2sbref \
		  -omat ../reg/$( basename ${anat} )2sbref_fsl.mat \
		  -searchry -90 90 -searchrx -90 90 -searchrz -90 90
	echo "Affining for ANTs"
	c3d_affine_tool -ref ${sbref}_brain -src ${anat}_brain \
	../reg/$( basename ${anat} )2sbref_fsl.mat -fsl2ras -oitk ../reg/$( basename ${anat} )2sbref0GenericAffine.mat
fi

cd ${cwd}
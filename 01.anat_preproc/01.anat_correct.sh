#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "anat_in adir"
echo "Optional:"
echo "aref tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
aref=none
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-anat_in)	anat_in=$2;shift;;
		-adir)		adir=$2;shift;;

		-aref)		aref=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar anat_in adir
checkoptvar aref tmp

### Remove nifti suffix
for var in anat_in aref
do
	eval "${var}=${!var%.nii*}"
done

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${adir} || exit 1

#Read and process input
anat=$( basename ${anat_in%.nii.gz} )
if_missing_do mkdir ${tmp}

## 02. Bias Field Correction with ANTs
# 02.1. Truncate (0.01) for Bias Correction
echo "Performing BFC on ${anat}"
ImageMath 3 ${tmp}/${anat}_trunc.nii.gz TruncateImageIntensity ${anat_in}.nii.gz 0.02 0.98 256
# 02.2. Bias Correction
N4BiasFieldCorrection -d 3 -i ${tmp}/${anat}_trunc.nii.gz -o ${tmp}/${anat}_bfc.nii.gz

## 03. Anat coreg between modalities
if [[ "${aref}" != "none" ]]
then
	arefsfx=$( basename ${aref%_*} )
	arefsfx=${arefsfx#*ses-*_}
	echo "Flirting ${tmp}/${anat}_bfc on ${aref}"
	flirt -in ${tmp}/${anat}_bfc -ref ${aref} -cost normmi -searchcost normmi \
	-omat ../reg/${anat}2${arefsfx}_fsl.mat -o ../reg/${anat}2${arefsfx}_fsl.nii.gz
fi

cd ${cwd}
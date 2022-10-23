#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "mref_in fdir"
echo "Optional:"
echo "anat mask aseg"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anat=none
mask=none
aseg=none

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-mref_in)	mref_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-anat)			anat=$2;shift;;
		-mask)			mask=$2;shift;;
		-aseg)			aseg=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar mref_in fdir
checkoptvar anat mask aseg

### Remove nifti suffix
for var in mref_in anat mask aseg
do
	eval "${var}=${!var%.nii*}"
done

### Catch errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
mref=$( basename ${mref_in%_*} )

## 01. Motion Computation, if more than 1 volume
if [[ "${mask}" == "none" ]]
then
	echo "BETting ${mref}"
	bet ${mref_in} ../reg/${mref}_brain -R -f 0.5 -g 0 -n -m
else
	# 01.4. Apply mask
	echo "BETting ${mref} with given mask"
	fslmaths ${mref_in} -mas ${mask} ../reg/${mref}_brain
fi

## 02. Anat Coreg
mrefsfx=$( basename ${mref} )
mrefsfx=${mref#sub-*_}
mrefsfx=${mrefsfx#ses-*_}
anat2mref=../reg/${anat}2${mrefsfx}0GenericAffine

if [[ "${anat}" != "none" && ! -e "${anat2mref}.mat" ]]
then
	echo "Coregistering ${mref} to ${anat}"
	if_missing_do stop ${anat}_brain.nii.gz
	flirt -in ${anat}_brain -ref ../reg/${mref}_brain -out ${anat}2${mrefsfx} \
		  -omat ${anat}2${mrefsfx}_fsl.mat \
		  -searchry -90 90 -searchrx -90 90 -searchrz -90 90
	echo "Affining for ANTs"
	c3d_affine_tool -ref ../reg/${mref}_brain -src ${anat}_brain \
	${anat}2${mrefsfx}_fsl.mat -fsl2ras -oitk ${anat}2${mrefsfx}0GenericAffine.mat
	mv ${anat}2${mrefsfx}* ../reg/.
fi

asegsfx=$( basename ${aseg} )
asegsfx=${aseg#sub-*_}
asegsfx=${asegsfx#*ses-*_}
if [[ "${aseg}" != "none" && -e "${aseg}_seg.nii.gz" && ! -e "${aseg}_seg2mref.nii.gz" ]]
then
	echo "Coregistering anatomical segmentation to ${mref}..."
	if [[ "${aseg}" != "${anat}" && -e "../reg/${anat}2${asegsfx}0GenericAffine.mat" ]]
	then
		echo "...in 2 steps"
		antsApplyTransforms -d 3 -i ${aseg}_seg.nii.gz \
							-r ../reg/${mref}_brain.nii.gz -o ${aseg}_seg2mref.nii.gz \
							-n Multilabel -v \
							-t ${anat2mref}.mat \
							-t [../reg/${anat}2${asegsfx}0GenericAffine.mat,1]
	else
		echo "...in 1 step"
		antsApplyTransforms -d 3 -i ${aseg}_seg.nii.gz \
							-r ../reg/${mref}_brain.nii.gz -o ${aseg}_seg2mref.nii.gz \
							-n Multilabel -v \
							-t ${anat2mref}.mat
	fi
fi

cd ${cwd}
#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "dref ddir anat"
echo "Optional:"
echo "mask aseg tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
aseg=none
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-dref)		dref=$2;shift;;
		-ddir)		ddir=$2;shift;;
		-anat)		anat=$2;shift;;

		-mask)			mask=$2;shift;;
		-aseg)			aseg=$2;shift;;
		-tmp)			tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar dref ddir anat
checkoptvar mask aseg tmp

### Remove nifti suffix
for var in anat dref mask aseg
do
	eval "${var}=${!var%.nii*}"
done

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${ddir} || exit

# Bet dref if necessary
if [[ ! -e "${dref}_brain_mask" && "${mask}" == "none" ]]
then
	echo "BETting reference ${dref}"
	bet ${dref} ${tmp}/${dref}_brain -R -f 0.5 -g 0 -n -m
	mask=${dref}_brain_mask
	immv ${tmp}/${dref}_brain_mask ${mask}
elif [[ "${mask}" != "none" ]]
then
	flsmaths ${dref} -mas ${mask} ${dref}_brain
else
	mask=${dref}_brain_mask
fi
flsmaths ${dref} -mas ${mask} ../reg/${dref}_brain

## 02. Anat Coreg
drefsfx=$( basename ${dref} )
drefsfx=${dref#*sub-*_}
anat2dref=../reg/${anat}2${drefsfx}0GenericAffine

if [[ ! -e "${anat2dref}.mat" ]]
then
	echo "Coregistering ${dref} to ${anat}"
	flirt -in ${anat}_brain -ref ../reg/${dref}_brain -out ${anat}2${drefsfx} -omat ${anat}2${drefsfx}_fsl.mat \
	-cost normmi -searchcost normmi \
	-searchry -90 90 -searchrx -90 90 -searchrz -90 90
	echo "Affining for ANTs"
	c3d_affine_tool -ref ../reg/${dref}_brain -src ${anat}_brain \
	${anat}2${drefsfx}_fsl.mat -fsl2ras -oitk ${anat}2${drefsfx}0GenericAffine.mat
	mv ${anat}2${drefsfx}* ../reg/.
fi

asegsfx=$( basename ${aseg} )
asegsfx=${aseg#*ses-*_}
if [[ "${aseg}" != "none" && -e "../anat/${aseg}_seg.nii.gz" && -e "../reg/${anat}2${asegsfx}0GenericAffine.mat" && ! -e "../anat/${aseg}_seg2dref.nii.gz" ]]
then
	echo "Coregistering anatomical segmentation to ${dref}"
	antsApplyTransforms -d 3 -i ../anat/${aseg}_seg.nii.gz \
						-r ../reg/${dref}_brain.nii.gz -o ../anat/${aseg}_seg2dref.nii.gz \
						-n Multilabel -v \
						-t ${anat2dref}.mat \
						-t [../reg/${anat}2${asegsfx}0GenericAffine.mat,1]
fi

cd ${cwd}
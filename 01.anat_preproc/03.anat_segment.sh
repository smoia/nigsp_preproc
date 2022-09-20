#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "anat_in adir"
echo "Optional:"
echo "tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-anat_in)		anat_in=$2;shift;;
		-adir)		adir=$2;shift;;

		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar anat_in adir
checkoptvar tmp

### Remove nifti suffix
anat_in=${anat_in%.nii*}

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${adir} || exit

#Read and process input
anat=$( basename ${anat_in%_*} )
if_missing_do mkdir ${tmp}

## 01. Atropos (segmentation)
# 01.1. Run Atropos
echo "Segmenting ${anat}"
Atropos -d 3 -a ${anat_in}.nii.gz \
-o ${anat}_seg.nii.gz \
-x ${anat}_brain_mask.nii.gz -i kmeans[3] \
--use-partial-volume-likelihoods \
-s 1x2 -s 2x3 \
-v 1

## 02. Split, erode & dilate
echo "Splitting the segmented files, eroding and dilating"
3dcalc -a ${anat}_seg.nii.gz -expr 'equals(a,1)' -prefix ${tmp}/${anat}_CSF.nii.gz -overwrite
3dcalc -a ${anat}_seg.nii.gz -expr 'equals(a,3)' -prefix ${anat}_WM.nii.gz -overwrite
3dcalc -a ${anat}_seg.nii.gz -expr 'equals(a,2)' -prefix ${anat}_GM.nii.gz -overwrite

dicsf=-2
diwm=-3

3dmask_tool -input ${tmp}/${anat}_CSF.nii.gz -prefix ${tmp}/${anat}_CSF_eroded.nii.gz -dilate_input ${dicsf} -overwrite
3dmask_tool -input ${anat}_WM.nii.gz -prefix ${tmp}/${anat}_WM_eroded.nii.gz -fill_holes -dilate_input ${diwm} -overwrite
3dmask_tool -input ${anat}_GM.nii.gz -prefix ${anat}_GM_dilated.nii.gz -dilate_input 2 -overwrite
fslmaths ${anat}_GM_dilated -mas ${anat_in}_mask ${anat}_GM_dilated

#!# Further release: Check number voxels > compcorr components
until [ "$(fslstats ${tmp}/${anat}_CSF_eroded -p 100)" != "0" -o "${dicsf}" == "0" ]
do
	let dicsf+=1
	echo "Too much erosion, setting new erosion to ${dicsf}"
	3dmask_tool -input ${tmp}/${anat}_CSF.nii.gz -prefix ${tmp}/${anat}_CSF_eroded.nii.gz -dilate_input ${dicsf} -overwrite
done 
until [ "$(fslstats ${tmp}/${anat}_WM_eroded -p 100)" != "0" -o "${diwm}" == "0" ]
do
	let diwm+=1
	echo "Too much erosion, setting new erosion to ${diwm}"
	3dmask_tool -input ${anat}_WM.nii.gz -prefix ${tmp}/${anat}_WM_eroded.nii.gz -fill_holes -dilate_input ${diwm} -overwrite
done

# Checking that the CSF mask doesn't cointain GM
echo "Checking that the CSF doesn't contain GM"
fslmaths ${tmp}/${anat}_CSF_eroded -sub ${anat}_GM_dilated.nii.gz -thr 0 ${tmp}/${anat}_CSF_eroded

# Recomposing masks
echo "Recomposing the eroded maps into one volume"
fslmaths ${anat}_GM -mul 2 ${anat}_GM
fslmaths ${tmp}/${anat}_WM_eroded -sub ${tmp}/${anat}_CSF -thr 0 -mul 3 -add ${tmp}/${anat}_CSF_eroded -add ${anat}_GM ${anat}_seg_eroded

cd ${cwd}
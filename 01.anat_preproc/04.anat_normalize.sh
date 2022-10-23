#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "anat_in adir std mmres"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

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
		-std)		std_in=$2;shift;;
		-mmres)		mmres=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar anat_in adir std_in mmres

### Remove nifti suffix
for var in anat_in std_in
do
	eval "${var}=${!var%.nii*}"
done

### Catch errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${adir} || exit

#Read and process input
anat=$( basename ${anat_in} )
std=$( basename ${std_in} )

if_missing_do stop ${anat}.nii.gz

## 01. Normalization
[[ "${std}" != "${std_in}" ]] && if_missing_do copy ${std_in}.nii.gz ../reg/${std}.nii.gz
if_missing_do stop ../reg/${std}.nii.gz
if_missing_do mask ../reg/${std}.nii.gz ../reg/${std}_mask.nii.gz

anatsfx=${anat#*ses-*_}
anatprx=${anat%_${anatsfx}}
echo "Normalizing ${anat} to ${std}"
antsRegistration -d 3 -r [../reg/${std}.nii.gz,${anat}.nii.gz,1] \
				 -o [../reg/${anat}2std,../reg/${anat}2std.nii.gz,../reg/${anatprx}_std2${anatsfx}.nii.gz] \
				 -x [../reg/${std}_mask.nii.gz, ${anat_in}_mask.nii.gz] \
				 -n Linear -u 0 -w [0.005,0.995] \
				 -t Rigid[0.1] \
				 -m MI[../reg/${std}.nii.gz,${anat_in}.nii.gz,1,48,Regular,0.1] \
				 -c [1000x500x250x100,1e-6,10] \
				 -f 8x4x2x1 \
				 -s 3x2x1x0vox \
				 -t Affine[0.1] \
				 -m MI[../reg/${std}.nii.gz,${anat_in}.nii.gz,1,48,Regular,0.1] \
				 -c [1000x500x250x100,1e-6,10] \
				 -f 8x4x2x1 \
				 -s 3x2x1x0vox \
				 -t SyN[0.1,3,0] \
				 -m CC[../reg/${std}.nii.gz,${anat_in}.nii.gz,1,5] \
				 -c [100x70x50x20,1e-6,10] \
				 -f 8x4x2x1 \
				 -s 3x2x1x0vox \
				 -z 1 -v 1 --float 0

## 02. Registration to downsampled MNI
cd ../reg || exit

if [ ! -e ${std}_resamp_${mmres}mm.nii.gz ]
then
	echo "Resampling ${std} at ${mmres}mm"
	ResampleImageBySpacing 3 ${std}.nii.gz ${std}_resamp_${mmres}mm.nii.gz ${mmres} ${mmres} ${mmres} 0
	echo "Creating mask for ${std} at ${mmres}mm"
	fslmaths ../reg/${std}_resamp_${mmres}mm -bin ../reg/${std}_resamp_${mmres}mm_mask
fi

echo "Registering ${anat} to resampled standard"
antsApplyTransforms -d 3 -i ${anat_in}.nii.gz \
					-r ${std}_resamp_${mmres}mm.nii.gz -o ${anat}2std_resamp_${mmres}mm.nii.gz \
					-n Linear -t ${anat}2std1Warp.nii.gz -t ${anat}2std0GenericAffine.mat


cd ${cwd}
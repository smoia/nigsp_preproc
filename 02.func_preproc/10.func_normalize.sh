#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in anat mref std fdir"
echo "Optional:"
echo "mmres aref tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
mmres=0
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
		-func_in)	func_in=$2;shift;;
		-anat)		anat=$2;shift;;
		-mref)		mref=$2;shift;;
		-std)		std=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-mmres)		mmres=$2;shift;;
		-aref)		aref=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar func_in anat mref std fdir
checkoptvar mmres aref tmp

### Remove nifti suffix
for var in func_in anat mref std aref
do
	eval "${var}=${!var%.nii*}"
done

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${fdir} || exit

#Read and process input
func=$( basename ${func_in%_*} )

echo "Normalising ${func}"
ndim=$( fslval ${func_in} dim0 )

if [[ $(bc -l <<< "${mmres} > 0") -eq 1 ]]
then
	std="${std}_resamp_${mmres}mm"
fi

if_missing_do stop ${func_in}.nii.gz
if_missing_do stop ${std}.nii.gz
if_missing_do stop ../reg/${anat}2std1Warp.nii.gz
if_missing_do stop ../reg/${anat}2std0GenericAffine.mat

runantsApplyTransforms="antsApplyTransforms -d ${ndim} -i ${func_in}.nii.gz \
-r ../reg/${std}.nii.gz -o ${tmp}/${func}_std.nii.gz \
-n Linear \
-t ../reg/${anat}2std1Warp.nii.gz \
-t ../reg/${anat}2std0GenericAffine.mat"

mrefsfx=$( basename ${mref} )
mrefsfx=${mref#*ses-*_}

if [[ ${aref} != "none" ]]
then
	anatsfx=$( basename ${anat} )
	anatsfx=${anat#*ses-*_}
	if_missing_do stop ../reg/${aref}2${anatsfx}0GenericAffine.mat
	if_missing_do stop ../reg/${aref}2${mrefsfx}0GenericAffine.mat
	echo "Preparing three steps normalisation (two anats, one func)"
	runantsApplyTransforms="${runantsApplyTransforms} \
-t ../reg/${aref}2${anatsfx}0GenericAffine.mat \
-t [../reg/${aref}2${mrefsfx}0GenericAffine.mat,1]"
else
	if_missing_do stop ../reg/${anat}2${mrefsfx}0GenericAffine.mat
	echo "Preparing two steps normalisation (one anat, one func)"
	runantsApplyTransforms="${runantsApplyTransforms} \
-t [../reg/${anat}2${mrefsfx}0GenericAffine.mat,1]"
fi

echo "# Running the command:"
echo ""
echo "${runantsApplyTransforms}"
echo ""

eval ${runantsApplyTransforms}

cd ${cwd}

#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fdir"
echo "Optional:"
echo "anat_in adir mref aseg polort tmp"

exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anat_in=none
adir=none
mref=none
aseg=none
polort=4
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-func_in)	func_in=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-anat_in)	anat_in=$2;shift;;
		-adir)		adir=$2;shift;;
		-mref)		mref=$2;shift;;
		-aseg)		aseg=$2;shift;;
		-polort)		polort=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fdir
checkoptvar anat_in adir mref aseg polort tmp

### Remove nifti suffix
for var in func_in anat mref aseg
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
mref_in=${mref%.nii.gz}

if [[ "${adir}" != "none" ]]; then anat_in=${adir}/${anat_in}; fi
anat=$( basename ${anat_in} )
asegsfx=$( basename ${aseg} )
asegsfx=${asegsfx#*ses-*_}
mrefsfx=$( basename ${mref} )
mrefsfx=${mrefsfx#*ses-*_}

if [[ "${mref}" == "none" ]]; then mref=${func}; mref_in=${func_in}; fi
if [[ ! -e "${mref}_brain_mask.nii.gz" && ! -e "${mref}_mask.nii.gz" ]]
then
	echo "BETting reference ${mref}"
	bet ${mref_in} ${mref}_brain -R -f 0.5 -g 0 -n -m
	mref=${mref}_brain
fi

## 02. Anat Coreg

anat2mref=$( basename ${anat%.nii.gz})2sbref0GenericAffine

if [[ ! -e "../reg/${anat2mref}.mat" ]]
then
	echo "Coregistering ${anat} to ${func}"
	flirt -in ${anat}_brain -ref ${mref} -out ${tmp}/$( basename ${anat})2${mrefsfx} \
		  -omat ${tmp}/$( basename ${anat})2${mrefsfx}_fsl.mat \
		  -searchry -90 90 -searchrx -90 90 -searchrz -90 90
	echo "Affining for ANTs"
	c3d_affine_tool -ref ${mref} -src ${anat}_brain \
					${tmp}/$( basename ${anat})2${mrefsfx}_fsl.mat \
					-fsl2ras -oitk ${tmp}/${anat2mref}.mat

	anat2mref=${tmp}/${anat2mref}
else
	anat2mref=../reg/${anat2mref}
fi
if [[ "${adir}" != "none" ]]; then aseg=${adir}/$(basename ${aseg}); fi
if [[ ! -e "${aseg}_seg2sbref.nii.gz" ]]
then
	echo "Coregistering anatomical segmentation to ${func}"
	antsApplyTransforms -d 3 -i ${aseg}_seg.nii.gz \
						-r ${mref}.nii.gz -o ${aseg}_seg2sbref.nii.gz \
						-n Multilabel -v \
						-t ${anat2mref}.mat \
						-t [../reg/$( basename ${anat})2${asegsfx}0GenericAffine.mat,1]
fi
seg=${aseg}_seg2sbref
tmpseg=${tmp}/$( basename ${aseg} )_seg2sbref

3dcalc -a ${seg}.nii.gz -expr "a" -prefix ${tmpseg}.nii.gz -short -overwrite

#Plot some grayplots!

3dGrayplot -input ${func_in}.nii.gz -mask ${tmpseg}.nii.gz \
		   -prefix ${tmp}/${func}_gp_PVO.png -dimen 1800 1200 \
		   -polort ${polort} -pvorder -percent -range 3

cd ${cwd}
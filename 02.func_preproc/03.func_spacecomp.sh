#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fdir"
echo "Optional:"
echo "anat mref aseg antsaffine tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anat=none
mref=none
aseg=none
antsaffine=no
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

		-anat)			anat=$2;shift;;
		-mref)			mref=$2;shift;;
		-aseg)			aseg=$2;shift;;
		-antsaffine)	antsaffine=yes;;
		-tmp)			tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fdir
checkoptvar anat mref aseg antsaffine tmp

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

nTR=$(fslval ${func_in} dim4)
let nTR--

## 01. Motion Computation, if more than 1 volume

if [[ ${nTR} -gt 1 ]]
then
	# 01.1. Mcflirt
	if [[ "${mref}" == "none" ]]
	then
		echo "Creating a reference for ${func}"
		mref=${func}_ref
		fslroi ${func_in} ${mref} 42 1
	fi

	echo "McFlirting ${func}"
	if [[ -d ${tmp}/${func}_mcf.mat ]]; then rm -r ${tmp}/${func}_mcf.mat; fi
	mcflirt -in ${func_in} -r ${mref} -out ${tmp}/${func}_mcf -stats -mats -plots

	# 01.2. Demean motion parameters
	echo "Demean and derivate ${func} motion parameters"
	1d_tool.py -infile ${tmp}/${func}_mcf.par -demean -write ${func}_mcf_demean.par -overwrite
	1d_tool.py -infile ${func}_mcf_demean.par -derivative -demean -write ${func}_mcf_deriv1.par -overwrite

	# 01.3. Compute various metrics
	echo "Computing DVARS and FD for ${func}"
	fsl_motion_outliers -i ${tmp}/${func}_mcf -o ${tmp}/${func}_mcf_dvars_confounds -s ${func}_dvars_post.par -p ${func}_dvars_post --dvars --nomoco
	fsl_motion_outliers -i ${func_in} -o ${tmp}/${func}_mcf_dvars_confounds -s ${func}_dvars_pre.par -p ${func}_dvars_pre --dvars --nomoco
	fsl_motion_outliers -i ${func_in} -o ${tmp}/${func}_mcf_fd_confounds -s ${func}_fd.par -p ${func}_fd --fd
fi

if [[ ! -e "${mref}_brain_mask" && "${mref}" != "none" ]]
then
	echo "BETting reference ${mref}"
	bet ${mref} ${mref}_brain -R -f 0.5 -g 0 -n -m
fi

# 01.4. Apply mask
echo "BETting ${func}"
fslmaths ${tmp}/${func}_mcf -mas ${mref}_brain_mask ${tmp}/${func}_bet

## 02. Anat Coreg
mrefsfx=$( basename ${mref} )
mrefsfx=${mref#*ses-*_}
anat2mref=../reg/${anat}2${mrefsfx}0GenericAffine

if [[ "${anat}" != "none" && ! -e "${anat2mref}.mat" ]]
then
	echo "Coregistering ${func} to ${anat}"
	flirt -in ${anat}_brain -ref ${mref}_brain -out ${anat}2${mrefsfx} -omat ${anat}2${mrefsfx}_fsl.mat \
	-cost normmi -searchcost normmi \
	-searchry -90 90 -searchrx -90 90 -searchrz -90 90
	echo "Affining for ANTs"
	c3d_affine_tool -ref ${mref}_brain -src ${anat}_brain \
	${anat}2${mrefsfx}_fsl.mat -fsl2ras -oitk ${anat}2${mrefsfx}0GenericAffine.mat
	mv ${anat}2${mrefsfx}* ../reg/.
fi

asegsfx=$( basename ${aseg} )
asegsfx=${aseg#*ses-*_}
if [[ "${aseg}" != "none" && -e "../anat/${aseg}_seg.nii.gz" && -e "../reg/${anat}2${asegsfx}0GenericAffine.mat" && ! -e "../anat/${aseg}_seg2mref.nii.gz" ]]
then
	echo "Coregistering anatomical segmentation to ${func}"
	antsApplyTransforms -d 3 -i ../anat/${aseg}_seg.nii.gz \
						-r ${mref}.nii.gz -o ../anat/${aseg}_seg2mref.nii.gz \
						-n Multilabel -v \
						-t ${anat2mref}.mat \
						-t [../reg/${anat}2${asegsfx}0GenericAffine.mat,1]
fi

## 03. Split and affine to ANTs if required
if [[ "${antsaffine}" == "yes" ]]
then

	echo "Splitting ${func}"
	replace_and mkdir ${tmp}/${func}_split
	replace_and mkdir ../reg/${func}_mcf_ants_mat
	fslsplit ${func_in} ${tmp}/${func}_split/vol_ -t

	for i in $( seq -f %04g 0 ${nTR} )
	do
		echo "Affining volume ${i} of ${nTR} in ${func}"
		c3d_affine_tool -ref ${mref}_brain -src ${tmp}/${func}_split/vol_${i}.nii.gz \
		${tmp}/${func}_mcf.mat/MAT_${i} -fsl2ras -oitk ../reg/${func}_mcf_ants_mat/v${i}2${mrefsfx}.mat
	done
	rm -r ${tmp}/${func}_split
fi

# Moving things around
if [[ -d ../reg/${func}_mcf.mat ]]; then rm -r ../reg/${func}_mcf.mat; fi
mv ${tmp}/${func}_mcf.mat ../reg/.

if [[ "${mref}" == "${func}_avgref" ]]
then
	mv ${mref}* ../reg/.
fi

cd ${cwd}
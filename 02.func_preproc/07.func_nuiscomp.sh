#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fmat_in mref fdir"
echo "Optional:"
echo "aseg anat adir applynuisance motthr outthr polort den_motreg den_detrend den_meica den_tissues tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
aseg=none
anat=none
adir=none
applynuisance=no
motthr=0.3
outthr=0.05
polort=4
den_motreg=no
den_detrend=no
den_meica=no
den_tissues=no
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
		-fmat_in)	fmat_in=$2;shift;;
		-mref)		mref=$2;shift;;
		-fdir)		fdir=$2;shift;;

		-aseg)			aseg=$2;shift;;
		-anat)			anat=$2;shift;;
		-adir)			adir=$2;shift;;
		-applynuisance)	applynuisance=yes;;
		-motthr)		motthr=$2;shift;;
		-outthr)		outthr=$2;shift;;
		-polort)		polort=$2;shift;;
		-den_motreg)	den_motreg=yes;;
		-den_detrend)	den_detrend=yes;;
		-den_meica)		den_meica=yes;;
		-den_tissues)	den_tissues=yes;;
		-tmp)			tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fmat_in mref fdir
checkoptvar aseg anat adir applynuisance motthr outthr polort den_motreg den_detrend den_meica den_tissues tmp

### Remove nifti suffix
for var in func_in mref aseg anat
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
func=$( basename ${func_in%_*} )
fmat=$( basename ${fmat_in%.nii.gz} )

# Extract average tissue
if [[ "${adir}" != "none" ]]; then aseg=${adir}/${aseg}; fi
if [[ -e "${aseg}_seg_eroded.nii.gz" ]] &&  [[ "${den_tissues}" == "yes" ]]
then
	if [[ ! -e "${aseg}_seg2mref.nii.gz" || ! -e "${aseg}_GM_native.nii.gz" ]]
	then
		echo "Missing segmentation in native space"
		asegsfx=$( basename ${aseg} )
		asegsfx=${aseg#*ses-*_}
		if_missing_do stop ../reg/$( basename ${anat})2mref0GenericAffine.mat
		if_missing_do stop ../reg/$( basename ${anat})2${asegsfx}0GenericAffine.mat

		echo "Coregistering segmentations to ${func}"
		antsApplyTransforms -d 3 -i ${aseg}_seg_eroded.nii.gz -r ${mref}.nii.gz \
		-o ${aseg}_seg2mref.nii.gz -n MultiLabel \
		-t ../reg/$( basename ${anat})2mref0GenericAffine.mat \
		-t [../reg/$( basename ${anat})2${asegsfx}0GenericAffine.mat,1]
		antsApplyTransforms -d 3 -i ${aseg}_GM_dilated.nii.gz -r ${mref}.nii.gz \
		-o ${aseg}_GM_native.nii.gz -n MultiLabel \
		-t ../reg/$( basename ${anat})2mref0GenericAffine.mat \
		-t [../reg/$( basename ${anat})2${asegsfx}0GenericAffine.mat,1]
	fi
	echo "Extracting average WM and CSF in ${func}"
	3dDetrend -polort ${polort} -prefix ${tmp}/${func}_dtd.nii.gz ${func_in}.nii.gz -overwrite
	fslmeants -i ${tmp}/${func}_dtd.nii.gz -o ${func}_avg_tissue.1D --label=${aseg}_seg2mref.nii.gz
else
	echo "Skip average tissue extraction"
fi

## 04. Nuisance computation
# 04.1. Preparing censoring of fd > b & c > d in AFNI format
echo "Preparing censoring"
1deval -a ${fmat}_fd.par -b=${motthr} -c ${func}_outcount.1D -d=${outthr} -expr 'isnegative(a-b)*isnegative(c-d)' > ${func}_censors.1D

# 04.2. Create matrix
echo "Preparing nuisance matrix"

run3dDeconvolve="3dDeconvolve -input ${func_in}.nii.gz -float \
-censor ${func}_censors.1D \
-x1D ${func}_nuisreg_censored_mat.1D -xjpeg ${func}_nuisreg_mat.jpg \
-x1D_uncensored ${func}_nuisreg_uncensored_mat.1D \
-x1D_stop"


if [[ "${den_detrend}" == "yes" ]]
then
	echo "Consider trends"
	run3dDeconvolve="${run3dDeconvolve} -polort ${polort}"
else
	echo "Skip trends"
fi

if [[ "${den_motreg}" == "yes" ]]
then
	echo "Consider motion parameters"
	run3dDeconvolve="${run3dDeconvolve} -ortvec ${fmat}_mcf_demean.par motdemean \
 -ortvec ${fmat}_mcf_deriv1.par motderiv1"
else
	echo "Skip motion parameters"
fi

if [[ "${den_meica}" == "yes" ]]
then
	if_missing_do stop ${fmat}_rej_ort.1D
	echo "Consider meica"
	run3dDeconvolve="${run3dDeconvolve} -ortvec ${fmat}_rej_ort.1D meica"
else
	echo "Skip meica"
fi

if [[ "${den_tissues}" == "yes" ]]
then
	if_missing_do stop ${func}_avg_tissue.1D
	echo "Consider average tissues"
	run3dDeconvolve="${run3dDeconvolve} -num_stimts  2 \
 -stim_file 1 ${func}_avg_tissue.1D'[0]' -stim_base 1 -stim_label 1 CSF \
 -stim_file 2 ${func}_avg_tissue.1D'[2]' -stim_base 2 -stim_label 2 WM"
else
	echo "Skip average tissue denoising"
fi

# Report the 3dDeconvolve call

echo "######################################################"
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "# Running 3d Deconvolve with the following parameters:"
echo "   + Denoise motion regressors:         ${den_motreg}"
echo "   + Denoise legendre polynomials:      ${den_detrend}"
echo "   + Denoise meica rejected components: ${den_meica}"
echo "   + Denoise average tissues signal:    ${den_tissues}"
echo ""
echo "# Generating the command:"
echo ""
echo "${run3dDeconvolve}"
echo ""
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "######################################################"

eval ${run3dDeconvolve}
## 06. Nuisance

if [[ "${applynuisance}" == "yes" ]]
then
	echo "Actually applying nuisance"
	fslmaths ${func_in} -Tmean ${tmp}/${func}_avg
	3dTproject -polort 0 -input ${func_in}.nii.gz  -mask ${mref}_brain_mask.nii.gz \
	-ort ${func}_nuisreg_uncensored_mat.1D -prefix ${tmp}/${func}_prj.nii.gz \
	-overwrite
	fslmaths ${tmp}/${func}_prj -add ${tmp}/${func}_avg ${tmp}/${func}_den.nii.gz
fi

cd ${cwd}

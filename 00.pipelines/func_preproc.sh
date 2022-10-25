#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses wdr"
echo "Optional:"
echo "anat aseg voldiscard polort mref mask slicetimeinterp \
	  despike fwhm den_motreg den_detrend den_meica den_tissues \
	  applynuisance only_echoes only_optcom scriptdir tmp debug"
exit ${1:-0}
}

# Check if there is input
if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anat=none
aseg=none
fmap_str=none
fullfmap=none
voldiscard=10
polort=4
slicetimeinterp=none
despike=no
mref=default
mask=default
den_motreg=no
den_detrend=no
den_tissues=no
applynuisance=no
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
scriptdir=${scriptdir%/*}/02.func_preproc
debug=no
fwhm=none

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sub)		sub=$2;shift;;
		-ses)		ses=$2;shift;;
		-wdr)		wdr=$2;shift;;

		-anat)				anat=$2;shift;;
		-aseg)				aseg=$2;shift;;
		-fmap_str)			fmap_str=$2;shift;;
		-fullfmap)			fullfmap=$2;shift;;
		-voldiscard)		voldiscard=$2;shift;;
		-polrot)			polort=$2;shift;;
		-mref)				mref=$2;shift;;
		-mask)				mask=$2;shift;;
		-fwhm)				fwhm=$2;shift;;
		-slicetimeinterp)	slicetimeinterp=$2;shift;;
		-despike)			despike=yes;;
		-den_motreg)		den_motreg=yes;;
		-den_detrend)		den_detrend=yes;;
		-den_tissues)		den_tissues=yes;;
		-applynuisance)		applynuisance=yes;;
		-scriptdir)			scriptdir=$2;shift;;
		-tmp)				tmp=$2;shift;;
		-debug)				debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses wdr
[[ ${scriptdir: -1} == "/" ]] && scriptdir=${scriptdir%/}
[[ ${mref} == "default" ]] && mref=${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_mref
[[ ${mask} == "default" ]] && mask=${mref}_brain_mask
checkoptvar anat aseg fmap_str fullfmap voldiscard polort mref mask slicetimeinterp despike fwhm den_motreg den_detrend den_tissues applynuisance scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in anat aseg fullfmap
do
	eval "${var}=${!var%.nii*}"
done

#Derived variables
fileprx=sub-${sub}_ses-${ses}
[[ ${tmp} != "." ]] && fileprx=${tmp}/${fileprx}
fdir=${wdr}/sub-${sub}/ses-${ses}/func
bold=${fileprx}_task-rest_bold
######################################
#########    Task preproc    #########
######################################

echo "************************************"
echo "*** Func correct rest BOLD"
echo "************************************"
echo "************************************"

runfunccorrect="${scriptdir}/01.func_correct.sh -func_in ${bold} -fdir ${fdir}"
runfunccorrect="${runfunccorrect} -voldiscard ${voldiscard}"
runfunccorrect="${runfunccorrect} -slicetimeinterp ${slicetimeinterp} -tmp ${tmp}"
[[ ${despike} == "yes" ]] && runfunccorrect="${runfunccorrect} -despike"

echo "# Generating the command:"
echo ""
echo "${runfunccorrect}"
echo ""

eval ${runfunccorrect}


if [[ "${mref}" == "none" ]]
then
	echo "************************************"
	echo "*** Func create MREF"
	echo "************************************"
	echo "************************************"

	# Create mref
	mref=${bold}_ref
	nTR=$(fslval ${bold}_cr dim4)
	if [[ "${nTR}" -gt "42" ]]; then volref=42; else volref=1; fi
	fslroi ${bold}_cr ${mref} ${volref} 1

	echo "************************************"
	echo "*** Func Fieldmap MREF BOLD"
	echo "************************************"
	echo "************************************"
	# Apply fieldmap to mref
	${scriptdir}/02.func_fieldmap.sh -func_in ${mref} -fdir ${fdir} \
									 -fmap_str ${fmap_str} -fullfmap ${fullfmap} \
									 -tmp ${tmp}


	# Set fullfmap to new value, move real mref to reg folder, and set tmp_mref for future bold movement correction
	[[ "${fullfmap}" == "none" ]] && fullfmap=${fdir}/$( basename ${bold} )_fieldmap/fmap_rads
	tmp_mref=${mref}
	mref=${fdir}/../reg/sub-${sub}_mref
	immv ${bold}_fmd ${mref}

	echo "************************************"
	echo "*** Func spacecomp MREF BOLD"
	echo "************************************"
	echo "************************************"

	[[ "${mask}" == "default" ]] && mask=none
	# BET mref and compute anat coreg to it 
	${scriptdir}/11.mref_spacecomp.sh -mref_in ${mref} -fdir ${fdir} -anat ${anat} \
									  -mask ${mask} -aseg ${aseg}

	# If mask exists copy it in reg folder
	[[ "${mask}" != "none" ]] && imcp ${mask} ${mref}_brain_mask
	mask=${mref}_brain_mask

else
	tmp_mref=${mref}
fi

echo "************************************"
echo "*** Func spacecomp rest"
echo "************************************"
echo "************************************"

${scriptdir}/03.func_spacecomp.sh -func_in ${bold}_cr -fdir ${fdir} \
								  -mref ${tmp_mref} -tmp ${tmp}


echo "************************************"
echo "*** Func Fieldmap rest BOLD"
echo "************************************"
echo "************************************"

${scriptdir}/02.func_fieldmap.sh -func_in ${bold}_mcf -fdir ${fdir} \
								 -fmap_str ${fmap_str} -fullfmap ${fullfmap} \
								 -tmp ${tmp}

# Apply mask to the output of func_fieldmap
fslmaths ${bold}_fmd -mas ${mask} ${bold}_bet


# echo "************************************"
# echo "*** Func greyplot rest BOLD (pre)"
# echo "************************************"
# echo "************************************"

# ${scriptdir}/12.func_grayplot.sh -func_in ${bold}_cr -fdir ${fdir} -anat_in ${anat} \
# 								 -mref ${mref} -aseg ${aseg} -polort 4 -tmp ${tmp}

# boldout=$( basename ${bold%_*} )
# echo "mv ${bold}_gp_PVO.png ${fdir}/${boldout}_raw_gp_PVO.png"
# mv ${bold}_gp_PVO.png ${fdir}/${boldout}_raw_gp_PVO.png
# echo "mv ${bold}_gp_IJK.png ${fdir}/${boldout}_raw_gp_IJK.png"
# mv ${bold}_gp_IJK.png ${fdir}/${boldout}_raw_gp_IJK.png
# echo "mv ${bold}_gp_peel.png ${fdir}/${boldout}_raw_gp_peel.png"
# mv ${bold}_gp_peel.png ${fdir}/${boldout}_raw_gp_peel.png

	
echo "************************************"
echo "*** Func Nuiscomp rest BOLD"
echo "************************************"
echo "************************************"

fmat=${fdir}/$( basename ${bold} )

runnuiscomp="${scriptdir}/07.func_nuiscomp.sh -func_in ${bold}_bet -fmat_in ${fmat}"
runnuiscomp="${runnuiscomp} -mref ${mref} -fdir ${fdir} -tmp ${tmp}"
runnuiscomp="${runnuiscomp} -anat ${anat} -aseg ${aseg} -polort ${polort}"
[[ ${den_motreg} == "yes" ]] && runnuiscomp="${runnuiscomp} -den_motreg"
[[ ${den_detrend} == "yes" ]] && runnuiscomp="${runnuiscomp} -den_detrend"
[[ ${den_meica} == "yes" ]] && runnuiscomp="${runnuiscomp} -den_meica"
[[ ${den_tissues} == "yes" ]] && runnuiscomp="${runnuiscomp} -den_tissues"
[[ ${applynuisance} == "yes" ]] && runnuiscomp="${runnuiscomp} -applynuisance" && boldsource=${bold}_den
[[ ${applynuisance} == "no" ]] && boldsource=${bold}_bet

echo "# Generating the command:"
echo ""
echo "${runnuiscomp}"
echo ""

eval ${runnuiscomp}

boldout=$( basename ${bold} )
if [[ ${fwhm} != "none" ]]
then

	echo "************************************"
	echo "*** Func smoothing rest BOLD"
	echo "************************************"
	echo "************************************"

	${scriptdir}/08.func_smooth.sh -func_in ${boldsource} -fdir ${fdir} -fwhm ${fwhm} -mask ${mask} -tmp ${tmp}
	boldsource=${bold}_sm
fi

echo "3dcalc -a ${boldsource}.nii.gz -b ${mask}.nii.gz -expr 'a*b' -prefix ${fdir}/00.${boldout}_native_preprocessed.nii.gz -short -gscale"
3dcalc -a ${boldsource}.nii.gz -b ${mask}.nii.gz -expr 'a*b' \
	   -prefix ${fdir}/00.${boldout}_native_preprocessed.nii.gz \
	   -short -gscale -overwrite

# echo "************************************"
# echo "*** Func greyplot rest BOLD (post)"
# echo "************************************"
# echo "************************************"
# ${scriptdir}/12.func_grayplot.sh -func_in ${boldsource} -fdir ${fdir} -anat_in ${anat} \
# 								 -mref ${mref} -aseg ${aseg} -polort 4 -tmp ${tmp}

# echo "mv ${bold}_gp_PVO.png ${fdir}/00.${boldout}_native_preprocessed_gp_PVO.png"
# mv ${bold}_gp_PVO.png ${fdir}/00.${boldout}_native_preprocessed_gp_PVO.png
# echo "mv ${bold}_gp_IJK.png ${fdir}/00.${boldout}_native_preprocessed_gp_IJK.png"
# mv ${bold}_gp_IJK.png ${fdir}/00.${boldout}_native_preprocessed_gp_IJK.png
# echo "mv ${bold}_gp_peel.png ${fdir}/00.${boldout}_native_preprocessed_gp_peel.png"
# mv ${bold}_gp_peel.png ${fdir}/00.${boldout}_native_preprocessed_gp_peel.png


[[ ${debug} == "yes" ]] && set +x

#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses wdr"
echo "Optional:"
echo "{axial sagittal coronal} direc anat aseg mask pepolar bval bvec acqparams sliceorder mporder repol scriptdir tmp debug"
exit ${1:-0}
}

# Check if there is input
if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
axis="-axial"
direc=AP
anat=none
aseg=none
mask=default
pepolar=none
bval=default
bvec=default
acqparams=default
sliceorder=none
mporder=6
repol=no
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
scriptdir=${scriptdir%/*}/03.dwi_preproc
debug=no

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

		-axial)			axis="-axial";;
		-sagittal)		axis="-sagittal";;
		-coronal)		axis="-coronal";;
		-direction)		direc=$2;shift;;
		-anat)			anat=$2;shift;;
		-aseg)			aseg=$2;shift;;
		-mask)			mask=$2;shift;;
		-pepolar)		pepolar=$2;shift;;
		-bval)			bval=$2;shift;;
		-bvec)			bvec=$2;shift;;
		-acqparams)		acqparams=$2;shift;;
		-sliceorder)	sliceorder=$2;shift;;
		-mporder)		mporder=$2;shift;;
		-repol)			repol=yes;;
		-scriptdir)		scriptdir=$2;shift;;
		-tmp)			tmp=$2;shift;;
		-debug)			debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses wdr
[[ ${scriptdir: -1} == "/" ]] && scriptdir=${scriptdir%/}
checkoptvar axis direc anat aseg mask pepolar bval bvec acqparams sliceorder mporder repol scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in anat aseg mask
do
	eval "${var}=${!var%.nii*}"
done

#Derived variables
fileprx=sub-${sub}_ses-${ses}
ddir=${wdr}/sub-${sub}/ses-${ses}/dwi
dwi=${fileprx}_dir-${direc}_dwi
bforward=${fileprx}_dir-$( echo ${direc} | rev )_dwi
[[ ${tmp} != "." ]] && dwi=${tmp}/${dwi} && bforward=${tmp}/${bforward}
######################################
#########     DWI preproc    #########
######################################

echo "************************************"
echo "*** DWI correct  $( basename ${dwi})"
echo "************************************"
echo "************************************"

${scriptdir}/01.dwi_correct.sh -dwi_in ${dwi} -ddir ${ddir} ${axis} -tmp ${tmp}
dwisource=${tmp}/${dwi}_cr


echo "************************************"
echo "*** DWI correct  $( basename ${bforward})"
echo "************************************"
echo "************************************"

${scriptdir}/01.dwi_correct.sh -dwi_in ${bforward} -ddir ${ddir} ${axis} -tmp ${tmp}
bforsource=${tmp}/${bforward}_cr


echo "************************************"
echo "*** DWI Pepolar"
echo "************************************"
echo "************************************"

${scriptdir}/02.dwi_pepolar.sh -breverse ${dwisource} -bforward ${bforsource} \
							   -ddir ${ddir} -pepolar ${pepolar} -bval ${bval} -bvec ${bvec} \
							   -acqparams ${acqparams} -tmp ${tmp}  # -applytopup

[[ ${pepolar} == "none" ]] && pepolar=${dwi}_topup


echo "************************************"
echo "*** DWI Eddy"
echo "************************************"
echo "************************************"

rundwieddy="${scriptdir}/03.dwi_eddy.sh -dwi_in ${tmp}/${dwi}_cr -pepolar ${pepolar}"
rundwieddy="${rundwieddy} -ddir ${ddir} -mask ${mask} -sliceorder ${sliceorder}"
rundwieddy="${rundwieddy} -mporder ${mporder} -tmp ${tmp}"
[[ ${repol} == "yes" ]] && rundwieddy="${rundwieddy} -repol"

echo ""
echo "-----------------------------------------------------------"
echo "# Generating the command:"
echo "${rundwieddy}"
echo "-----------------------------------------------------------"
echo ""

eval ${rundwieddy}

[[ ${mask} == none ]] && mask=${ddir}/${dwi}_brain_mask


echo "************************************"
echo "*** DWI Spacecomp "
echo "************************************"
echo "************************************"

${scriptdir}/04.dwi_spacecomp.sh -dref ${ddir}/${dwi}_brain -ddir ${ddir} -anat ${anat} \
								 -mask ${mask} -aseg ${aseg} -tmp ${tmp}


[[ ${debug} == "yes" ]] && set +x

exit 0

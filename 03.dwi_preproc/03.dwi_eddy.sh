#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "dwi_in pepolar ddir"
echo "Optional:"
echo "mask repol sliceorder mporder tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
mask=none
repol=no
sliceorder=none
mporder=6
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-dwi_in)	dwi_in=$2;shift;;
		-pepolar)	pepolar=$2; shift;;
		-ddir)		ddir=$2;shift;;

		-mask)			mask=$2;shift;;
		-repol)			repol=yes;;
		-sliceorder)	sliceorder=$2;shift;;
		-mporder)		mporder=$2;shift;;
		-tmp)			tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar dwi_in pepolar ddir
checkoptvar mask repol sliceorder mporder tmp

### Remove nifti suffix
dwi_in=${dwi_in%.nii*}
mask=${mask%.nii*}

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${ddir} || exit

#Read and process input
dwi=${dwi_in#*dir-??}
dwi=$( basename ${dwi_in%_dir*} )${dwi%_*}
dinfo=${dwi_in%_*}

# If no mask was specified, create a temporary one.
if [[ ${mask} == "none" ]]
then
	fslmaths ${pepolar}/mgdmap -Tmean ${tmp}/${dwi}_avg
	bet ${tmp}/${dwi}_avg ${tmp}/${dwi}_brain -R -f 0.5 -g 0 -n -m
	mask=${tmp}/${dwi}_brain_mask
fi

echo "Prepare eddy command for ${dwi}"
runeddy="eddy --imain=${dwi_in}.nii.gz --mask=${mask}.nii.gz --acqp=${dinfo}_acqparams.txt"
runeddy="${runeddy} --index=${dinfo}_index.txt --bvecs=${dinfo}.bvec --bvals=${dinfo}.bval"
# runeddy="${runeddy} --niter=8" 
runeddy="${runeddy} --topup=${pepolar}/outtp --niter=8" 
# --fwhm=10,8,4,2,0,0,0,0"
runeddy="${runeddy} --out=${tmp}/${dwi}_eddy --data_is_shelled -v"

[[ ${repol} == "yes" ]] && runeddy="${runeddy} --repol"
[[ ${sliceorder} != "none" ]] && runeddy="${runeddy} --mporder=${mporder} --slspec=${sliceorder} --s2v_niter=5 --s2v_lambda=1 --s2v_interp=trilinear"

echo ""
echo "-----------------------------------------------------------"
echo "# Generating the command:"
echo ${runeddy}
echo "-----------------------------------------------------------"
echo ""

eval ${runeddy}

#### USE ROTATED BVECS FROM EDDY

# Bet if necessary and get reference
dwiextract -bzero -fslgrad ${dinfo}.bvec ${dinfo}.bval ${tmp}/${dwi}_eddy.nii.gz ${tmp}/${dwi}_b0.nii.gz

[[ ${mask} == "none" ]] && bet ${tmp}/${dwi}_b0 ${ddir}/${dwi}_brain -R -f 0.5 -g 0 -n -m
[[ ${mask} != "none" ]] && fslmaths ${tmp}/${dwi}_b0 -mas ${mask} ${ddir}/${dwi}_brain

fslmaths ${tmp}/${dwi}_eddy -mas ${dwi}_brain_mask ${ddir}/00.${dwi}_preprocessed

cd ${cwd}

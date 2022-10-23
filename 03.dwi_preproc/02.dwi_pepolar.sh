#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "breverse bforward ddir"
echo "Optional:"
echo "pepolar bval bvec acqparams applytopup tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
pepolar=none
bval=default
bvec=default
acqparams=default
applytopup=no
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-breverse)	breverse=$2;shift;;
		-bforward)	bforward=$2;shift;;
		-ddir)		ddir=$2;shift;;

		-pepolar)		pepolar=$2;shift;;
		-bval)			bval=$2;shift;;
		-bvec)			bvec=$2;shift;;
		-acqparams)		acqparams=$2;shift;;
		-applytopup) 	applytopup=yes;;
		-tmp)			tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar breverse bforward ddir
checkoptvar pepolar bval bvec acqparams applytopup tmp

### Remove nifti suffix
for var in breverse bforward
do
	eval "${var}=${!var%.nii*}"
done

### Catch errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${ddir} || exit

#Read and process input
dwi=${breverse#*dir-??}
dwi=$( basename ${breverse%_dir*} )${dwi%_*}

## 01. PEpolar
# If there isn't an estimated field, make it.
echo "Preparing PEpolar map computation"
if_missing_do stop ${breverse}.nii.gz
if_missing_do stop ${bforward}.nii.gz

[[ ${pepolar} == "none" ]] && pepolar=${dwi}_topup

if_missing_do mkdir ${pepolar}

echo "Extract B0 volumes and concatenate acqparams"
if [[ ${bval} == "default" ]]
then
	bvalrev=${breverse%dwi_*}dwi.bval; bvalfor=${bforward%dwi_*}dwi.bval
fi
if [[ ${bvec} == "default" ]]
then
	bvecrev=${breverse%dwi_*}dwi.bvec; bvecfor=${bforward%dwi_*}dwi.bvec
fi
if [[ ${acqparams} == "default" ]]
then
	acqparamsrev=${breverse%dwi_*}dwi_acqparams.txt
	acqparamsfor=${bforward%dwi_*}dwi_acqparams.txt
fi

dwiextract -bzero -fslgrad ${bvecrev} ${bvalrev} ${breverse}.nii.gz ${tmp}/brev.nii.gz
dwiextract -bzero -fslgrad ${bvecfor} ${bvalfor} ${bforward}.nii.gz ${tmp}/bfor.nii.gz

if [[ ${acqparams} == "default" ]]
then
	nvol=$(fslval ${tmp}/brev.nii.gz dim4)
	yes $(cat ${acqparamsrev}) | head -n ${nvol} > ${tmp}/brev_acqp
	nvol=$(fslval ${tmp}/bfor.nii.gz dim4)
	yes $(cat ${acqparamsfor}) | head -n ${nvol} > ${tmp}/bfor_acqp
	cat ${tmp}/brev_acqp ${tmp}/bfor_acqp > ${pepolar}/acqparams.txt
fi

fslmerge -t ${pepolar}/mgdmap ${tmp}/brev ${tmp}/bfor

cd ${pepolar}
echo "Computing PEpolar map for ${dwi}"
topup --imain=mgdmap --datain=acqparams.txt --out=outtp --verbose
cd ..

# 02. Applying the warping to the dwi volume to get mask and reference
if [[ ${applytopup} == "yes" ]]
then
	echo "Applying PEPOLAR map on ${dwi}"
	applytopup --imain=${breverse} --datain=${pepolar}/acqparams.txt --inindex=1 \
	--topup=${pepolar}/outtp --out=${tmp}/${dwi}_tpp --verbose --method=jac
fi

cd ${cwd}
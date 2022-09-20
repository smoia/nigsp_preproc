#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fdir"
echo "Optional:"
echo "pepolar breverse bforward tmp scriptdir"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
pepolar=none
breverse=none
bforward=none
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
scriptdir=${scriptdir%/*}/..
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

		-pepolar)	pepolar=$2;shift;;
		-breverse)	breverse=$2;shift;;
		-bforward)	bforward=$2;shift;;
		-scriptdir)	scriptdir=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fdir
checkoptvar pepolar breverse bforward tmp scriptdir

### Remove nifti suffix
for var in anat_in breverse bforward
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

## 01. PEpolar
# If there isn't an estimated field, make it.
if [[ ${pepolar} == "none" && ${breverse} != "none" && ${bforward} != "none" ]]
then
	echo "Preparing PEpolar map computation"
	if_missing_do stop ${breverse}.nii.gz
	if_missing_do stop ${bforward}.nii.gz

	pepolar=${func}_topup

	mkdir ${pepolar}
	fslmerge -t ${pepolar}/mgdmap ${breverse} ${bforward}

	cd ${pepolar}
	echo "Computing PEpolar map for ${func}"
	topup --imain=mgdmap --datain=${scriptdir}/acqparam.txt --out=outtp --verbose
	cd ..
elif [[ ${pepolar} == "none" && ( ${breverse} == "none" || ${bforward} == "none" ) ]]
then
	checkoptvar breverse bforward 
	echo "PEpolar image computation requires both to be declared."
	exit 1
fi

# 03.2. Applying the warping to the functional volume
echo "Applying PEPOLAR map on ${func}"
applytopup --imain=${func_in} --datain=${scriptdir}/acqparam.txt --inindex=1 \
--topup=${pepolar}/outtp --out=${tmp}/${func}_tpp --verbose --method=jac

cd ${cwd}
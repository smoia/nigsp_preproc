#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "func_in fdir"
echo "Optional:"
echo "fwhm mask tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
fwhm=5
mask=none
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

		-fwhm)		fwhm=$2;shift;;
		-mask)		mask=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar func_in fdir
checkoptvar fwhm mask tmp

### Remove nifti suffix
for var in func_in mask
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

## 01. Smooth
echo "Smoothing ${func}"
run3dBlurInMask="3dBlurInMask -input ${func_in}.nii.gz -prefix ${tmp}/${func}_sm.nii.gz \
-preserve -FWHM ${fwhm} -overwrite"

if [[ ${mask} != "none" ]]
then
	echo "Blur in mask using ${mask}"
	run3dBlurInMask="${run3dBlurInMask} -mask ${mask}.nii.gz"
else
	echo "# Blurring full volume - are you sure???"
fi

echo "# Running the command:"
echo ""
echo "${run3dBlurInMask}"
echo ""

eval ${run3dBlurInMask}

cd ${cwd}
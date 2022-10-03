#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "dwi_in ddir"
echo "Optional:"
echo "axial sagittal coronal despike slicetimeinterp tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
axes="0,1"
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-dwi_in)	dwi_in=$2;shift;;
		-ddir)		ddir=$2;shift;;

		-axial)		axes="0,1";;
		-sagittal)	axes="1,2";;
		-coronal)	axes="0,2";;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar dwi_in ddir
checkoptvar axes tmp

### Remove nifti suffix
dwi_in=${dwi_in%.nii*}

######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${ddir} || exit

#Read and process input
dwi=$( basename ${dwi_in%.nii.gz} )

# Start correctign images
echo "Estimate and remove noise in ${dwi}"
dwidenoise ${dwi_in}.nii.gz ${tmp}/${dwi}_den.nii.gz

echo "Remove Gibbs ringing Artifacts in ${dwi}"
mrdegibbs -axes ${axes} ${tmp}/${dwi}_den.nii.gz ${tmp}/${dwi}_cr.nii.gz

## 03. Copy over bval, bvec, acqparams, and index
cp ${dwi_in%.nii.gz}.bval ${tmp}/.
cp ${dwi_in%.nii.gz}.bvec ${tmp}/.
cp ${dwi_in%.nii.gz}_acqparams.txt ${tmp}/.
cp ${dwi_in%.nii.gz}_index.txt ${tmp}/.

cd ${cwd}
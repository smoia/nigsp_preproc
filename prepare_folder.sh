#!/usr/bin/env bash

# shellcheck source=./utils.sh
source $(dirname "$0")/utils.sh

displayhelp() {
echo "Required:"
echo "sub ses wdr std prjname"
echo "Optional:"
echo "overwrite stdpath tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
overwrite=no
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
stdpath=${scriptdir}/90.template
mmres=no

### print input
printline=$( basename -- $0 )
echo "${printline} " "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-sub)		sub=$2;shift;;
		-ses)		ses=$2;shift;;
		-wdr)		wdr=$2;shift;;
		-std)		std=$2;shift;;
		-prjname)	prjname=$2;shift;;

		-overwrite)	overwrite=yes;;
		-stdpath)	stdpath=$2;shift;;
		-mmres)		mmres=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Derivate variables
if [[ -z ${tmp+x} ]]
then
	tmp=${wdr}
fi
tmp=${tmp}/tmp_${prjname}_${sub}

# Check input
checkreqvar sub ses wdr std prjname
checkoptvar overwrite stdpath mmres tmp

######################################
######### Script starts here #########
######################################

# saving the current wokdir
cwd=$(pwd)

echo "************************************"
echo "*** Preparing folders"
echo "************************************"
echo "************************************"

cd ${wdr} || ( echo "${wdr} not found" && exit )

# Start build path
sourcepath="${wdr}"

if [[ -d "rawdata" ]]
then
	sourcepath="${sourcepath}/rawdata"
fi

echo "Checking if the selected session folder exists"
if_missing_do stop ${sourcepath}/sub-${sub}/ses-${ses}

echo "Overwrite tmp folder"
replace_and mkdir ${tmp}

echo "Check derivative project folder"
if_missing_do mkdir derivatives/${prjname}

sesfld=derivatives/${prjname}/sub-${sub}/ses-${ses}

[[ "${overwrite}" == "yes" ]] && replace_and mkdir ${sesfld}

if_missing_do mkdir ${sesfld}/func ${sesfld}/anat \
					${sesfld}/fmap ${sesfld}/reg \
					${sesfld}/dwi

echo "Initialise files"
if_missing_do copy ${stdpath}/${std}.nii.gz ${sesfld}/reg/${std}.nii.gz
[[ -e ${stdpath}/${std}_resamp_${mmres}mm.nii.gz ]] && imcp ${stdpath}/${std}_resamp_${mmres}mm.nii.gz \
															${sesfld}/reg/${std}_resamp_${mmres}mm.nii.gz

imcp ${sourcepath}/sub-${sub}/ses-${ses}/func/*.nii.gz ${tmp}/.
imcp ${sourcepath}/sub-${sub}/ses-${ses}/anat/*.nii.gz ${tmp}/.
imcp ${sourcepath}/sub-${sub}/ses-${ses}/fmap/*.nii.gz ${tmp}/.
cp ${sourcepath}/sub-${sub}/ses-${ses}/fmap/*.json ${tmp}/.
imcp ${sourcepath}/sub-${sub}/ses-${ses}/dwi/*.nii.gz ${tmp}/.

cd ${cwd}

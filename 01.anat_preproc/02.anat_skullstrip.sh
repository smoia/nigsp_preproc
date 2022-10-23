#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "anat_in adir"
echo "Optional:"
echo "mask aref {bet 3dSS} c3dsource tmp"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
mask=none
aref=none
brain_extract=3dSS
c3dsource=none
tmp=.

### print input
printline=$( basename -- $0 )
echo "${printline}" "$@"
# Parsing required and optional variables with flags
# Also checking if a flag is the help request or the version
while [ ! -z "$1" ]
do
	case "$1" in
		-anat_in)	anat_in=$2;shift;;
		-adir)		adir=$2;shift;;

		-mask)		mask=$2;shift;;
		-aref)		aref=$2;shift;;
		-bet)		brain_extract=bet;;
		-3dSS)		brain_extract=3dSS;;
		-c3dsource)	c3dsource=$2;shift;;
		-tmp)		tmp=$2;shift;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar anat_in adir
checkoptvar mask aref brain_extract c3dsource tmp

### Remove nifti suffix
for var in anat_in mask aref
do
	eval "${var}=${!var%.nii*}"
done

### Catch errors and exit on them
set -e
######################################
######### Script starts here #########
######################################

cwd=$(pwd)

cd ${adir} || exit

#Read and process input
anat=$( basename ${anat_in%_*} )

if [[ "${mask}" == "none" ]]
then
	# If no mask is specified, then creates it.
	echo "Skull Stripping ${anat}"
	if [[ "${brain_extract}" == "3dSS" ]]
	then
		3dSkullStrip -input ${anat_in}.nii.gz \
					 -prefix ${tmp}/${anat}_brain.nii.gz \
					 -orig_vol -overwrite
		# Momentarily forcefully change header because SkullStrips plumbs the volume.
		3dcalc -a ${anat_in}.nii.gz -b ${tmp}/${anat}_brain.nii.gz -expr "a*step(b)" \
			   -prefix ${anat}_brain.nii.gz -overwrite
		fslmaths ${anat}_brain -bin ${anat}_brain_mask
	elif [[ "${brain_extract}" == "bet" ]]
	then
		bet ${anat_in} ${anat}_brain  -R -f 0.5 -g 0 -n -m
	fi
	mask=${anat}_brain_mask
	echo ""
else
	# If a mask is specified, use it.
	# Check if user input is basename or mask itself.
	if [[ -e "${mask}_brain_mask.nii.gz" ]]
	then
		mask=${mask}_brain_mask
	fi
	echo "Masking ${anat}"
	fslmaths ${anat_in} -mas ${mask} ${anat}_brain
	fslmaths ${anat}_brain -bin ${anat}_brain_mask
fi

arefsfx=$( basename ${aref%_*} )
arefsfx=${aref#*ses-*_}

if [[ "${aref}" != "none" ]] && [[ -e ../reg/${anat}2${arefsfx}_fsl.mat ]]
then
	# If a reference is specified, coreg the mask to the reference
	echo "Flirting ${mask} into ${aref}"
	flirt -in ${mask} -ref ${aref} -cost normmi -searchcost normmi \
		  -init ../reg/${anat}2${arefsfx}_fsl.mat -o ${aref}_brain_mask \
		  -applyxfm -interp nearestneighbour
fi

if [[ "${c3dsource}" != "none" ]]
then
	c3dfile=$(basename ${c3dsource})
	anatsfx=${anat#*ses-*_}

	# If a source for c3d is specified,
	# translate fsl transformation into ants with the right images.
	echo "Moving from FSL to ants in brain extracted images"
	c3d_affine_tool -ref ${anat}_brain -src ${c3dsource}_brain ../reg/${c3dfile}2${anatsfx}_fsl.mat \
				    -fsl2ras -oitk ../reg/${c3dfile}2${anatsfx}0GenericAffine.mat
	# Also transform both skullstripped and not!
	antsApplyTransforms -d 3 -i ${c3dsource}_brain.nii.gz \
						-r ${anat}_brain.nii.gz -o ../reg/${c3dfile}_brain2${anatsfx}_brain.nii.gz \
						-n Linear -t ../reg/${c3dfile}2${anatsfx}0GenericAffine.mat
	# antsApplyTransforms -d 3 -i ${c3dsource}.nii.gz \
	# 					-r ${anat}.nii.gz -o ../reg/${c3dsource}2${anatsfx}.nii.gz \
	# 					-n Linear -t ../reg/${c3dsource}2${anatsfx}0GenericAffine.mat
fi

cd ${cwd}
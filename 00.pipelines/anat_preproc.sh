#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses wdr"
echo "Optional:"
echo "anat1sfx anat2sfx std mmres normalise scriptdir tmp debug"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
anat1sfx=acq-mp2rage_T1w
anat2sfx=acq-mp2rage_inv-2_MP2RAGE
std=MNI152_1mm_T1_brain
mmres=2
normalise=no
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
scriptdir=${scriptdir%/*}/01.anat_preproc
debug=no

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

		-anat1sfx)	anat1sfx=$2;shift;;
		-anat2sfx)	anat2sfx=$2;shift;;
		-std)		std=$2;shift;;
		-mmres)		mmres=$2;shift;;
		-normalise) normalise=yes;;
		-scriptdir)	scriptdir=$2;shift;;
		-tmp)		tmp=$2;shift;;
		-debug)		debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses wdr
[[ ${scriptdir: -1} == "/" ]] && scriptdir=${scriptdir%/}
checkoptvar anat1sfx anat2sfx std mmres normalise scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in anat1sfx anat2sfx std
do
	eval "${var}=${!var%.nii*}"
done

#Derived variables
anat1=sub-${sub}_ses-${ses}_${anat1sfx}
adir=${wdr}/sub-${sub}/ses-${ses}/anat
[[ ${tmp} != "." ]] && anat1=${tmp}/${anat1}
######################################
#########    Anat preproc    #########
######################################

echo "************************************"
echo "*** Anat correction  $( basename ${anat1})"
echo "************************************"
echo "************************************"

${scriptdir}/01.anat_correct.sh -anat_in ${anat1} -adir ${adir} -tmp ${tmp}

if [[ ${anat2sfx} != "none" ]]
then
	anat2=sub-${sub}_ses-${ses}_${anat2sfx}
	[[ ${tmp} != "." ]] && anat2=${tmp}/${anat2}
	echo "************************************"
	echo "*** Anat correction $( basename ${anat2})"
	echo "************************************"
	echo "************************************"

	${scriptdir}/01.anat_correct.sh -anat_in ${anat2} -adir ${adir} \
									-aref ${anat1}_bfc -tmp ${tmp}

	echo "************************************"
	echo "*** Anat skullstrip $( basename ${anat2})"
	echo "************************************"
	echo "************************************"

	${scriptdir}/02.anat_skullstrip.sh -anat_in ${anat2}_bfc -adir ${adir} \
									   -aref ${anat1} -bet

	echo "************************************"
	echo "*** Anat skullstrip $( basename ${anat1})"
	echo "************************************"
	echo "************************************"

	${scriptdir}/02.anat_skullstrip.sh -anat_in ${anat1}_bfc -adir ${adir} \
									   -mask ${anat1}_brain_mask \
									   -c3dsource ${adir}/$( basename ${anat2})
else
	echo "************************************"
	echo "*** Anat skullstrip $( basename ${anat1})"
	echo "************************************"
	echo "************************************"

	${scriptdir}/02.anat_skullstrip.sh -anat_in ${anat1}_bfc -adir ${adir}
fi

echo "************************************"
echo "*** Anat segment $( basename ${anat1})"
echo "************************************"
echo "************************************"

${scriptdir}/03.anat_segment.sh -anat_in ${adir}/$( basename ${anat1})_brain -adir ${adir} -tmp ${tmp}

if [[ ${normalise} == "yes" ]]
then
	echo "************************************"
	echo "*** Anat normalise $( basename ${anat1})"
	echo "************************************"
	echo "************************************"

	${scriptdir}/04.anat_normalize.sh -anat_in ${adir}/$( basename ${anat1})_brain -adir ${adir} \
									  -std ${std} -mmres ${mmres}
fi

[[ ${debug} == "yes" ]] && set +x

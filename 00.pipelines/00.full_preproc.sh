#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses prjname wdr"
echo "Optional:"
echo "anatsfx asegsfx voldiscard sbref mask slicetimeinterp despike fwhm scriptdir tmp debug"
exit ${1:-0}
}

# Check if there is input

if [[ ( $# -eq 0 ) ]]
	then
	displayhelp
fi

# Preparing the default values for variables
overwrite=no
run_prep=yes
run_anat=yes
anat1sfx=acq-uni_T1w
anat2sfx=T2w

std=MNI152_1mm_T1_brain
mmres=2
normalise=no
voldiscard=10
slicetimeinterp=none
despike=no
sbref=none
mask=default
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
debug=no
fwhm=none

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
		-prjname)	prjname=$2;shift;;

		-TEs)				TEs="$2";shift;;
		-tasks)				tasks="$2";shift;;
		-anat1sfx)			anat1sfx=$2;shift;;
		-anat2sfx)			anat2sfx=$2;shift;;
		-std)				std=$2;shift;;
		-mmres)				mmres=$2;shift;;
		-normalise) 		normalise=yes;;
		-voldiscard)		voldiscard=$2;shift;;
		-sbref)				sbref=$2;shift;;
		-mask)				mask="$2";shift;;
		-fwhm)				fwhm="$2";shift;;
		-slicetimeinterp)	slicetimeinterp="$2";shift;;
		-despike)			despike=yes;;
		-scriptdir)			scriptdir=$2;shift;;
		-tmp)				tmp=$2;shift;;
		-overwrite)			overwrite=yes;;
		-skip_prep)			run_prep=no;;
		-skip_anat)			run_anat=no;;
		-debug)				debug=yes;;

		-h)			displayhelp;;
		-v)			version;exit 0;;
		*)			echo "Wrong flag: $1";displayhelp 1;;
	esac
	shift
done

# Check input
checkreqvar sub ses prjname wdr
[[ ${scriptdir: -1} == "/" ]] && scriptdir=${scriptdir%/}
checkoptvar anat1sfx anat2sfx voldiscard sbref mask slicetimeinterp despike fwhm scriptdir tmp debug

[[ ${debug} == "yes" ]] && set -x

### Remove nifti suffix
for var in anat1sfx anat2sfx std sbref mask
do
	eval "${var}=${!var%.nii*}"
done

#Derived variables
fileprx=sub-${sub}_ses-${ses}
[[ ${tmp} != "." ]] && fileprx=${tmp}/${fileprx}

first_ses_path=${wdr}/derivatives/${prjname}/sub-${sub}/ses-T1
uni_adir=${first_ses_path}/anat

####################

######################################
######### Script starts here #########
######################################

# Preparing log folder and log file, removing the previous one
if_missing_do mkdir ${wdr}/log
logfile=${wdr}/log/sub-${sub}_ses-${ses}_${prjname}_preproc_log


replace_and touch ${logfile}

echo "************************************" >> ${logfile}

exec 3>&1 4>&2

exec 1>${logfile} 2>&1

date
echo "************************************"


echo "************************************"
echo "***    Preproc sub ${sub} ses ${ses} ${prjname}"
echo "************************************"
echo "************************************"
echo ""
echo ""

######################################
#########   Prepare folders  #########
######################################

if [[ "${run_prep}" == "yes" ]]
then
	runprepfld="${scriptdir}/../prepare_folder.sh -sub ${sub} -ses ${ses}"
	runprepfld="${runprepfld} -wdr ${wdr} -std ${std} -mmres ${mmres}"
	runprepfld="${runprepfld} -tmp ${tmp} -prjname ${prjname}"
	if [[ "${overwrite}" == "yes" ]]
	then
		runprepfld="${runprepfld} -overwrite"
		run_anat=yes
	fi

	echo "# Generating the command:"
	echo ""
	echo "${runprepfld}"
	echo ""

	eval ${runprepfld}
fi

wdr=${wdr}/derivatives/${prjname}
tmp=${tmp}/tmp_${prjname}

######################################
#########    Anat preproc    #########
######################################

echo ""
echo ""

if [[ ${anat1sfx} != "none" ]]; then anat1=sub-${sub}_ses-T1_${anat1sfx}; else anat1=none; fi
if [[ ${anat2sfx} != "none" ]]; then anat2=sub-${sub}_ses-T1_${anat2sfx}; else anat2=none; fi

if [[ "${run_anat}" == "yes" ]]
then
	if [ ${ses} -eq 1 ]
	then
		# If asked & it's ses 01, run anat
		${scriptdir}/anat_preproc.sh -sub ${sub} -ses ${ses} -wdr ${wdr} \
												  -anat1sfx ${anat1sfx} -anat2sfx ${anat2sfx} \
												  -std ${std} -mmres ${mmres} -normalise \
												  -tmp ${tmp}
	elif [ ${ses} -lt 1 ]
	then
		echo "ERROR: the session number introduced makes no sense."
		echo "Please run a positive numbered session."
		exit 1
	elif [ ! -d ${uni_adir} ]
	then
		# If it isn't ses 01 but that ses wasn't run, exit.
		echo "ERROR: the universal anat folder,"
		echo "   ${uni_adir}"
		echo "doesn't exist. For the moment, this means the program quits"
		echo "Please run the first session of each subject first"
		exit 1
	elif [ -d ${uni_adir} ]
	then
		# If it isn't ses 01, and that ses was run, copy relevant files.
		mkdir -p ${wdr}/sub-${sub}/ses-${ses}/anat
		cp -R ${uni_adir}/* ${wdr}/sub-${sub}/ses-${ses}/anat/.
		# Then be sure that the anatomical files reference is right.
		cp ${uni_adir}/../reg/*${anat1}* ${wdr}/sub-${sub}/ses-${ses}/reg/.
		if [[ ${anat2} != "none" ]]
		then
			cp ${uni_adir}/../reg/*${anat2}* ${wdr}/sub-${sub}/ses-${ses}/reg/.
		fi
	fi
fi


######################################
#########    Task preproc    #########
######################################

echo ""
echo ""

aseg=${uni_adir}/${anat1}
anat=${uni_adir}/${anat2}
[[ ${sbref} == "default" ]] && sbref=${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref
[[ ${mask} == "default" ]] && mask=${sbref}_brain_mask

if [[ ${tasks} != "none" ]]
then
	for task in ${tasks}
	do
		runfuncpreproc="${scriptdir}/func_preproc.sh -sub ${sub} -ses ${ses}"
		runfuncpreproc="${runfuncpreproc} -task ${task} -TEs \"${TEs}\""
		runfuncpreproc="${runfuncpreproc} -wdr ${wdr} -anat ${anat} -aseg ${aseg}"
		runfuncpreproc="${runfuncpreproc} -voldiscard ${voldiscard} -slicetimeinterp ${slicetimeinterp}"
		runfuncpreproc="${runfuncpreproc} -sbref ${sbref}"
		runfuncpreproc="${runfuncpreproc} -mask ${mask} -fwhm ${fwhm} -tmp ${tmp}"
		runfuncpreproc="${runfuncpreproc} -den_motreg -den_detrend"
		
		if [[ ${task} != "breathhold" ]]
		then
			runfuncpreproc="${runfuncpreproc} -den_meica"
			if [[ ${task} == *"rest"* ]]
			then
				runfuncpreproc="${runfuncpreproc} -applynuisance"
			fi
		fi

		echo "# Generating the command:"
		echo ""
		echo "${runfuncpreproc}"
		echo ""

		eval ${runfuncpreproc}
	done
fi

echo ""
echo ""

date
echo "************************************"
echo "************************************"
echo "***      Preproc COMPLETE!       ***"
echo "************************************"
echo "************************************"

if [[ ${debug} == "yes" ]]; then set +x; else rm -rf ${tmp}; fi
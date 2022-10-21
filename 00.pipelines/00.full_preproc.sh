#!/usr/bin/env bash

# shellcheck source=../utils.sh
source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

displayhelp() {
echo "Required:"
echo "sub ses prjname wdr"
echo "Optional:"
echo "anat1sfx anat2sfx std mmres voldiscard sbref fmask dmask fwhm \
	  slicetimeinterp direc pepolar sliceorder mporder axis scriptdir \
	  tmp overwrite run_prep run_anat run_func run_dwi debug"
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
run_func=yes
run_dwi=yes

anat1sfx=acq-mp2rage_T1w
anat2sfx=acq-mp2rage_inv-2_MP2RAGE
std=MNI152_1mm_T1_brain
mmres=2
voldiscard=10
sbref=none
fmask=none
dmask=none
fwhm=none
slicetimeinterp=none
direc=AP
pepolar=none
sliceorder=none
mporder=6
axis="-axial"
tmp=.
scriptdir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
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
		-prjname)	prjname=$2;shift;;

		-anat1sfx)			anat1sfx=$2;shift;;
		-anat2sfx)			anat2sfx=$2;shift;;
		-std)				std=$2;shift;;
		-mmres)				mmres=$2;shift;;
		-voldiscard)		voldiscard=$2;shift;;
		-sbref)				sbref=$2;shift;;
		-fmask)				fmask="$2";shift;;
		-dmask)				dmask="$2";shift;;
		-fwhm)				fwhm="$2";shift;;
		-slicetimeinterp)	slicetimeinterp="$2";shift;;
		-direc)				direc="$2";shift;;
		-pepolar)			pepolar="$2";shift;;
		-sliceorder)		sliceorder="$2";shift;;
		-mporder)			mporder="$2";shift;;
		-axial)				axis="-axial";;
		-sagittal)			axis="-sagittal";;
		-coronal)			axis="-coronal";;
		-scriptdir)			scriptdir=$2;shift;;
		-tmp)				tmp=$2;shift;;
		-overwrite)			overwrite=yes;;
		-skip_prep)			run_prep=no;;
		-skip_anat)			run_anat=no;;
		-skip_func)			run_func=no;;
		-skip_dwi)			run_dwi=no;;
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
checkoptvar anat1sfx anat2sfx std mmres voldiscard sbref fmask dmask fwhm
checkoptvar slicetimeinterp direc pepolar sliceorder mporder axis scriptdir
checkoptvar tmp overwrite run_prep run_anat run_func run_dwi debug

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
		run_func=yes
		run_dwi=yes
	fi

	echo "# Generating the command:"
	echo ""
	echo "${runprepfld}"
	echo ""

	eval ${runprepfld}
fi

wdr=${wdr}/derivatives/${prjname}
tmp=${tmp}/tmp_${prjname}_${sub}

######################################
#########    Anat preproc    #########
######################################

echo ""
echo ""

if [[ ${anat1sfx} != "none" ]]; then anat1=sub-${sub}_ses-T1_${anat1sfx}; else anat1=none; fi
if [[ ${anat2sfx} != "none" ]]; then anat2=sub-${sub}_ses-T1_${anat2sfx}; else anat2=none; fi

if [[ "${run_anat}" == "yes" ]]
then
	if [ ${ses} == "T1" ]
	then
		# If asked & it's ses T1, run anat
		${scriptdir}/anat_preproc.sh -sub ${sub} -ses ${ses} -wdr ${wdr} \
									 -anat1sfx ${anat1sfx} -anat2sfx ${anat2sfx} \
									 -std ${std} -mmres ${mmres} -normalise \
									 -tmp ${tmp}
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
anat=${uni_adir}/${anat1}
[[ ${sbref} == "default" ]] && sbref=${wdr}/sub-${sub}/ses-${ses}/reg/sub-${sub}_sbref
[[ ${fmask} == "default" ]] && fmask=${sbref}_brain_mask

if [[ ${run_func} == "yes" ]]
then

	${scriptdir}/func_preproc.sh -sub ${sub} -ses ${ses} -wdr ${wdr} -anat ${anat} \
								 -aseg ${aseg} -voldiscard ${voldiscard} \
								 -slicetimeinterp ${slicetimeinterp} -sbref ${sbref} \
								 -mask ${fmask} -fwhm ${fwhm} -tmp ${tmp} \
								 -den_motreg -den_detrend -applynuisance

fi

echo ""
echo ""


######################################
#########    DWI preproc     #########
######################################

echo ""
echo ""

aseg=${uni_adir}/${anat1}
anat=${uni_adir}/${anat1}
[[ ${dmask} == "default" ]] && dmask=none

if [[ ${run_dwi} == "yes" ]]
then

	${scriptdir}/dwi_preproc.sh -sub ${sub} -ses ${ses} -wdr ${wdr} ${axis} \
								-direction ${direc} -anat ${anat} -aseg ${aseg} \
								-mask ${dmask} -pepolar ${pepolar} -sliceorder ${sliceorder} \
								-mporder ${mporder} -tmp ${tmp}

fi

echo ""
echo ""

date
echo "************************************"
echo "************************************"
echo "***      Preproc COMPLETE!       ***"
echo "************************************"
echo "************************************"

# if [[ ${debug} == "yes" ]]; then set +x; else rm -rf ${tmp}; fi
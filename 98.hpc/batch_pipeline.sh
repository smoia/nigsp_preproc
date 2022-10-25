#!/usr/bin/env bash

source $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/../utils.sh

##########################################################################################################################
##---START OF SCRIPT----------------------------------------------------------------------------------------------------##
##########################################################################################################################

date

list=${1}
sdir=${2:-"/scripts"}

checkreqvar list
checkoptvar sdir

mapfile -t sublist< <( cat ${list} )

[[ ${#sublist[@]} == 0 ]] && echo "given list ${list} is empty" && exit 1

# Run full preproc

for sub in "${sublist[@]}"
do
	sub=${sub#sub-}
	${sdir}/00.pipelines/00.full_preproc.sh -sub ${sub} -ses T1 -wdr /data -prjname preproc -tmp /tmp -fwhm 4 -skip_dwi
done

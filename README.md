Data processing for EuskalIBUR
==============================

This library is meant to run the data processing on the dataset *EuskalIBUR* (currently available on request).
It is meant to run in the container [*EuskalIBUR_Container*](https://git.bcbl.eu/smoia/euskalibur_container).

Warning
-------
At the moment, the container might not support graphic libraries and virtual screens, so some of the scripts that create figures (i.e. those using fsleyes or interactive matplotlib sessions) might not work properly in it. 

Scripts
-------

Scripts are organised into different folders:
- `01.anat_preproc`: Anatomical preprocessing. It can be applied to T1w (mp2rage) and T2w images.
	- `01.anat_correct.sh`: The volume is de-obliqued and reoriented in RPI. Then, a Bias Field Correction is applied, and if there's more than one modality, a linear co-registration (`flirt`) can be run. 
	- `02.anat_skullstrip.sh`: The volume is either skull-stripped (`3dSkullStrip`), or masked with an existing mask. Then, if there's a specified reference, the skullstripped brain mask is linearly registered to the reference. Finally, if requested, the translation between `FSL` and `ANTs` transformation is run.
	- `03.anat_segment.sh`: The volume is segmented (`Atropos`), then erosion is applied to the CSF and WM masks - being sure that there's at least one voxel. A dilated version of the GM is then subtracted from the two masks to be sure that they don't contain GM voxels.
	- `04.anat_normalize.sh`: The non-linear normalisation to the MNI152 template at 1 mm is computed (`antsRegistration`), and then the volume is resampled at the desired spatial resolution.

- `02.func_preproc`: Functional preprocessing (BOLD), also applied to SBRef volumes.
	- `01.func_correct.sh`: The volume is de-obliqued and reoriented in RPI. Then, the outlier fractions of each TR is computed against an average volume (`3dToutcount`). If asked, de-spiking and slice interpolation are run.
	- `02.func_pepolar.sh`: The PEPolar correction field is computed (`topup`) and/or applied (if already existing)
	- `03.func_spacecomp.sh`: Motion realignment to a given reference is computed (`mcflirt`) obtaining one transformation matrix per TR, then various metrics are computed on the six motion parameters. If the reference doesn't have a brain mask, it's computed (`bet`), then the input volume is masked with the same mask. After that, anatomical co-registration can be run (`flirt`). Finally, if required, the translation of the matrices from `FSL` to `ANTs` is computed too.
	- `04.func_realign.sh`: Strictly dependent from the output of `03.func_spacecomp.sh`, motion realignment is applied (`flirt`), followed by masking with the same brain mask computed earlier.
	- `05.func_meica.sh`: Different echo volumes are concatenated in space, and fed to `tedana`, that uses the PCA decomposition `kundu-stabilize`. Then, the bad components are orthogonalised with respect to the good ones.
	- `06.func_optcom.sh`: Different echo volumes are concatenated in space, and fed to `t2smap` to obtain an optimally combined volume. `3dToutcount` is run again on this volume.
	- `07.func_nuiscomp.sh`: The spatial average WM and CSF timeseries are computed, then censoring is computed, using excessive FD or outliers fractions. After that, the nuisance matrix is assembled with Legendre polynomials (5th order), WM and CSF timeseries, 12 motion parameters, tedana's rejected components, and both with and without censoring. If required (e.g. for resting states), the uncensored matrix is applied (`3dTproject`).
	- `08.func_smooth.sh`: The volume is smoothed.
	- `09.func_spc.sh`: The Signal Percentage Change of the volume is computed.
	- `10.func_normalize.sh`: The volume is normalised to a standard template, passing through two anatomical modalities (EPI > T2w > T1w > MNI)
	- `11.sbref_spacecomp.sh`: A modified version of `03.func_spacecomp.sh`, for single volumes (typically SBRef). The volume is brain-masked (`bet`), then anatomical co-registration can be run (`flirt`). Finally, the translation of the matrices from `FSL` to `ANTs` is computed too.

- `03.data_preproc`: Preprocessing for non-imaging data.
	- `01.sheet_preproc.sh`: calls `sheet_preproc.py`.
	- `02.prepare_CVR_mapping.sh`: *maybe obsolete*
	- `03.biopac_decimate.sh`: calls `biopac_decimate.py`
	- `04.biopac_preproc_token`: routine to be manually run on CO2 traces to obtain end-tidal PetCO2 regressors.
	- `05.compute_CVR_regressors.sh`: calls `compute_CVR_regressors.py`.

- `04.first_level_analysis`: Scripts for single session or single subject analysis.
	- `01.reg_manual_meica.sh`: Denoises BOLD volumes following a manual classification of components, either through partial regression (`fsl_regfilt`) or on orthogonalised "bad" components with respect to "good" ones (`3dTproject`).
	- `02.cvr_map.sh`: Applies a series of GLMs, using previously computed shifted versions of PetCO2 traces. Then, for each voxel, the highest R^2 value is found, and the corresponding shift is saved as lag and cvr map for that voxel. T values are also computed.
	- `03.compute_motion_outliers.sh`: DVARS and FD are computed on single echoes volumes, and optimally combined volumes denoised in different ways.

- `05.second_level_analysis`: Scripts that require multiple subjects, multiple sessions, or multiple denoising options.
	- `01.generalcvrmaps.sh`: *possibly obsolete*
	- `02.compare_motion_denoise.sh`: calls `compare_motion_denoise.py`.
	- `03.melodic_subject.sh`: runs `melodic` after realignment of sessions *to be updated*.
	- `04.motpar_ICA.sh`: *don't run*.

- `10.visualisation`: scripts to prepare 2d images of the results.
	- `01.plot_cvr_maps.sh`: Prepares CVR maps, both in single sessions (with lag, T values, corrected and uncorrected CVR maps) and across all the sessions.
	- `02.plot_motion_denoise.sh`: calls `plot_motion_denoise.py`
	- `03.plot_all_cvr_maps.sh`: prepares CVR maps comparing different denoising pipelines (needs `01.plot_cvr_maps.sh` outputs).
	- `04.plot_cvr_maps_properties.sh`: prepares data to run `compute_CVR_ICCs.py` and `plot_CVR_changes.py`.

- `99.cleaning`: utilities to make space deleting unused output from other scripts.
	- `01.physio_delete.sh`
	- `02.meica_delete.sh`
	- `03.func_delete.sh`
	- `04.anat_delete.sh`
	- `05.fmap_delete.sh`

A series of python scripts are included:
- `sheet_preproc.py`: a manual classification of components in a `.xlsx` file is split into a list of different types of components.
- `biopac_decimate.py`: 
- `compute_CVR_regressors.py`: 
- `compare_motion_denoise.py`: 
- `plot_motion_denoise.py`: 
- `compute_CVR_ICCs.py`: 
- `plot_CVR_changes.py`: 


Singularity container
---------------------
To run this scripts in a reproducible manner, a Singularity container has been created. It can found [here](https://git.bcbl.eu/smoia/euskalibur_container). For the moment, it has to be placed in the same folder as the scripts.


Preprocessing for BreathHold data
---------------------------------
`00.preproc.sh` has to be run on each subject and each session. Session 01 has to be run first.

To run it in the associated singularity container, e.g. for subject 003, first run session 01:
`singularity exec -B /path/to/data:/data -B /path/to/scripts:/scripts -B /path/to/tmp:/tmp euskalibur.sif 00.preproc.sh 003 01`
Then, the other sessions can be run in parallel.


### Anatomical preprocessing
For each subject, the T2w and the mp2rage volumes of the first session are preprocessed (`anat_preproc.sh`). The results are copied and used for all the other sessions.

The T2w and the mp2rage are de-obliqued and reoriented in RPI. Then, a Bias Field Correction is applied, and the T2w is registered to the mp2rage (`flirt`). 
The T2w is skull-stripped (`3dSkullStrip`), and the brain mask is used on the mp2rage after registration ().
The mp2rage is segmented (`Atropos`), and WM and CSF masks are slightly eroded.


### SBRef preprocessing
For each subject, the SBRef volume of the first session is preprocessed (`sbref_preproc.sh`). The results are copied and used for all the other sessions; the SBRef of the BreathHold of the first session is used as the reference for all the sessions for a subject.

The breathholds AP - PA acquisitions and the SBRef are de-obliqued and reoriented in RPI.
The PEPolar correction field is computed (`topup`) using the AP-PA volumes, and applied on the SBRef.
The SBRef is brain-masked (`bet`), then co-registered to the T2w of the first session (`flirt`). 


### BOLD preprocessing
For each subject and each session, the five echo volumes are preprocessed (`breathhold_preproc.sh`), and an optimally combined volume is obtained. All the volumes are registered to the first session breathhold SBRef.
*("volumes" will be omitted, referring only to "five echoes" or "first/second/.. echo")*

The five echoes are de-obliqued and reoriented in RPI. Then, the outlier fractions of each TR is computed against an average volume (`3dToutcount`).
Motion realignment to the SBRef of the first session's BreathHold is computed (`mcflirt`) using the first echo volume only. DVARS, FD, and twelve parameters are obtained. 
Motion realignment is applied to all the five echoes (`flirt`), then all the volumes are masked using the SBRef's brain mask.
The five echoes are concatenated in space, and fed to `tedana`, that uses the PCA decomposition `kundu-stabilize`. The ICs obtained are then manually classified into "noise", "vessel-like" components, "resting state networks", and "accepted" components.
The five echoes are also fed to `t2smap` to obtain an optimally combined volume. `3dToutcount` is run again on this volume.
The PEPolar correction field is applied on the five echoes and on the optimally combined volume (`topup`).
The Signal Percentage Change of all the volumes is computed.


### PetCO2 traces preprocessing


### CVR maps computation


### Comparison of different denoising pipelines

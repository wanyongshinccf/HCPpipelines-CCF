#!/bin/bash -e

#   Copyright (C) Cleveland Cllinic
#
#   SHCOPYRIGHT

# snipped from HCP script
source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@" 
source "$HCPPIPEDIR/global/scripts/newopts.shlib" "$@"
source ${HCPPIPEDIR}/global/scripts/tempfiles.shlib

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------
opts_SetScriptDescription "Regress out using AFNI commands for HCP pipeline"

opts_AddMandatory '--workingdir' 'WD' 'path' "working dir"

opts_AddMandatory '--infmri' 'InputfMRI' 'file' "input fMRI time series (NIFTI)"

opts_AddMandatory '--outfmri' 'OutputfMRI' 'string' "'name (prefix) to use for the output"

#Optional Args 
opts_AddOptional '--volregressor' 'VolumeMotion1D' '1dfile' "volumewise motion parameter regressors"

opts_AddOptional '--sliregressor' 'SliceMotion1D' '1dfile' "slicewise motion parameter regressors"

opts_AddOptional '--phyregressor' 'PhysioRegressor1D' '1dfile' "slicewise RETROICOR or PESTICA regressors"

opts_AddOptional '--voxregressor' 'PVTimeSeries' 'file' "Time-series Partial Volume map"

opts_AddMandatory '--scoutmask' 'ScoutInput_mask' 'mask' "Scout mask"

opts_ParseArguments "$@"

#display the parsed/default values
opts_ShowValues

# --- Report arguments

verbose_echo "  "
verbose_red_echo " ===> Running OneStepResampling_SLOMOCO"
verbose_echo " "
verbose_echo " Using parameters ..."
verbose_echo "         --workingdir: ${WD}"
verbose_echo "             --infmri: ${InputfMRI}"
verbose_echo "            --outfmri: ${OutputfMRI}"
verbose_echo "          --scoutmask: ${ScoutInput_mask}"
verbose_echo "       --volregressor: ${VolumeMotion1D}"
verbose_echo "       --sliregressor: ${SliceMotion1D}"
verbose_echo "       --voxregressor: ${PVTimeSeries}"
verbose_echo "       --phyregressor: ${PhysioRegressor1D}"
verbose_echo " "
\
# AFNI
if [ $FSLOUTPUTTYPE == "NIFTI_GZ" ]; then
    AFNIINPUTPOSTFIX="nii.gz"
elif [ $FSLOUTPUTTYPE == "NIFTI" ]; then
    AFNIINPUTPOSTFIX="nii"
fi

# step 0: if no mask is provided
if [[ ! -n ${ScoutInput_mask} ]]; then
    echo "Mask is not provided"
    echo "Mask is generated fron non-zero voxels"
    ScoutInput_mask=$WD/Scout_gdc_mask
    fslmaths $InputfMRI -Tmean -bin $ScoutInput_mask
fi


# Step 1; prepare volmot + polinomial detrending: Mendatory
if [[ -n $VolumeMotion1D ]] ; then
    1d_tool.py                          \
        -infile $VolumeMotion1D         \
        -demean                         \
        -write $WD/__rm.mopa6.demean.1D \
        -overwrite
    
    # volmopa includues the polinominal (linear) detrending 
    3dDeconvolve                                                                        \
        -input  ${InputfMRI}.$AFNIINPUTPOSTFIX                                          \
        -polort A                                                                       \
        -num_stimts 6                                                                   \
        -stim_file 1 $WD/__rm.mopa6.demean.1D'[0]' -stim_label 1 mopa1 -stim_base 1 	\
        -stim_file 2 $WD/__rm.mopa6.demean.1D'[1]' -stim_label 2 mopa2 -stim_base 2 	\
        -stim_file 3 $WD/__rm.mopa6.demean.1D'[2]' -stim_label 3 mopa3 -stim_base 3 	\
        -stim_file 4 $WD/__rm.mopa6.demean.1D'[3]' -stim_label 4 mopa4 -stim_base 4 	\
        -stim_file 5 $WD/__rm.mopa6.demean.1D'[4]' -stim_label 5 mopa5 -stim_base 5 	\
        -stim_file 6 $WD/__rm.mopa6.demean.1D'[5]' -stim_label 6 mopa6 -stim_base 6 	\
        -x1D         $WD/volreg.1D                                                      \
        -x1D_stop                                                                       \
        -overwrite
    volregstr="-matrix $WD/volreg.1D "
else
    3dDeconvolve                                                                        \
        -input  ${InputfMRI}.$AFNIINPUTPOSTFIX                                          \
        -polort A                                                                       \
        -x1D         $WD/polort.1D                                                      \
        -x1D_stop                                                                       \
        -overwrite

    volregstr="-matrix $WD/polort.1D "
fi

# step2 slimopa Optional
if [[ -n $SliceMotion1D ]]; then
    echo SliceMotion file is provided
    1d_tool.py                      \
        -infile $SliceMotion1D      \
        -demean                     \
        -write $WD/__rm.slimot.1D   \
        -overwrite

    # replace zero vectors with linear one
    \rm -f  $WD/slireg.1D
    python $SLOMOCODIR/patch_zeros.py    \
        -infile $WD/__rm.slimot.1D \
        -write  $WD/slireg.1D  
fi

if [[ -n $PhysioRegressor1D ]]; then
    1d_tool.py                          \
        -infile $PhysioRegressor1D      \
        -demean                         \
        -write $WD/phyreg.1D       \
        -overwrite
fi

if [[ -n $SliceMotion1D ]]; then
    # combine if physio file is provided
    if [[ -n $PhysioRegressor1D ]]; then
        python $SLOMOCODIR/combine_physio_slimopa.py    \
            -slireg $WD/slireg.1D                \
            -physio $WD/phyreg.1D                  \
            -write  $WD/slireg.phyreg.1D
        
        sliregstr="-slibase_sm $WD/slireg.phyreg.1D " 
    else
        sliregstr="-slibase_sm $WD/slireg.1D "
    fi
elif [[ -n $PhysioRegressor1D ]]; then
    sliregstr="-slibase_sm $WD/phyreg.1D " 
else
    sliregstr=" "
fi

# if voxelwise regressor is provided
if [[ -n $PVTimeSeries ]] ; then
    voxregstr="-dsort $PVTimeSeries.$AFNIINPUTPOSTFIX "
else
    voxregstr=" "
fi

# regress out all nuisances here
echo 3dREMLfit                                   \
    -input  ${InputfMRI}.$AFNIINPUTPOSTFIX  \
    $volregstr                              \
    $sliregstr                              \
    $voxregstr                              \
    -Oerrts $WD/errts.$AFNIINPUTPOSTFIX     \
    -GOFORIT                                \
    -overwrite 

3dREMLfit                                   \
    -input  ${InputfMRI}.$AFNIINPUTPOSTFIX  \
    $volregstr                              \
    $sliregstr                              \
    $voxregstr                              \
    -Oerrts $WD/errts.$AFNIINPUTPOSTFIX     \
    -GOFORIT                                \
    -overwrite 

# injected tissue contrast and make output
fslmaths $InputfMRI -Tmean $WD/__rm.mean
fslmaths $WD/__rm.mean -add $WD/errts.nii.gz $OutputfMRI

# clean
\rm -f  $WD/__rm.* # $WD/errts.* 

echo "Finished: 13 vol-/sli-/vox-wise motion nuisance regressors & "
echo "          polymonial detrending lines are regressed out."

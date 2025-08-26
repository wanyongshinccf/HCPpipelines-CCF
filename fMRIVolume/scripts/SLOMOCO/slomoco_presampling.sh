#!/bin/bash -e

#   Copyright (C) Cleveland Cllinic
#
#   SHCOPYRIGHT

Usage() {
    echo ""
    echo "Usage: slomoco_inplane.sh <4dinput> <4doutput> <MotionMatrixDir> <scout_image> <scount_image_mask> <SMSfactor>"
    echo ""
    exit
}

InputfMRI=`${FSLDIR}/bin/remove_ext ${1}`
OutputfMRI=`${FSLDIR}/bin/remove_ext ${2}`
GradientDistortionField=`${FSLDIR}/bin/remove_ext ${3}`
MotionMatrixFolder=${4} 
SLOMOCOFolder=${5} 
InplaneMotinFolder=${6} 
OutofPlaneMotionFolder=${7} 
SMSfactor=${8}

TESTWS=0
if [ $TESTWS -gt 0 ]; then
fMRIFolder=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL
InputfMRI=$fMRIFolder/rfMRI_REST1_RL_orig
OutputfMRI=$fMRIFolder/SLOMOCO/epi_gdc_mocoxy   
GradientDistortionField="$fMRIFolder"/rfMRI_REST1_RL_gdc_warp   
MotionMatrixFolder=$fMRIFolder/MotionMatrices
SLOMOCOFolder="$fMRIFolder"/SLOMOCO    
InplaneMotinFolder=$slomocodir/inplane
OutofPlaneMotionFolder=$slomocodir/outofplane  
SMSfactor=8              
fi

# read dimensions
zdim=`fslval $InputfMRI dim3`
tdim=`fslval $InputfMRI dim4`
tr=`fslval $InputfMRI pixdim4`
let "zmbdim=$zdim/$SMSfactor"

OneSamplingFolder=$SLOMOCOFolder/OneSampling
mkdir -p ${OneSamplingFolder}/prevols
mkdir -p ${OneSamplingFolder}/postvols

# Apply combined transformations to fMRI in a one-step resampling
# note that SLOMOCO is inplane motion correction output, according to SMS excitation
# (combines gradient non-linearity distortion, motion correction, and registration to atlas (MNI152) space, but keeping fMRI resolution)
${FSLDIR}/bin/fslsplit ${InputfMRI} ${OneSamplingFolder}/prevols/vol -t
FrameMergeSTRING=""
FrameMergeSTRINGII=""
for ((t=0; t < $tdim; t++)); do
    echo -ne "slomoco_presampling at volume $t \r"

    vnum=`${FSLDIR}/bin/zeropad $t 4`

    # Add stuff for estimating RMS motion
    volmatrix="${MotionMatrixFolder}/MAT_${vnum}"

    # split volxxxx.nii.gz to each slice for SLOMOCO 
    ${FSLDIR}/bin/fslsplit \
        ${OneSamplingFolder}/prevols/vol${vnum} \
        ${OneSamplingFolder}/prevols/sli -z
        
    # Start SLOMOCO
    SliceMergeSTRING="" 
    for ((z=0; z < $zdim; z++)); do
        let "zmb=$z%$SMSfactor" || true
        zmbnum=`${FSLDIR}/bin/zeropad $zmb 4`
        znum=`${FSLDIR}/bin/zeropad $z 4`
        slimatrix="${InplaneMotinFolder}/MAT/epiSMSsli_mc_mat_z${zmbnum}_t${vnum}"

        # concat vol + sli motion matrix
        convert_xfm -omat ${OneSamplingFolder}/prevols/volslimatrix -concat ${slimatrix} ${volmatrix}
        
        # Combine GCD with vol+sli motion correction
        ${FSLDIR}/bin/convertwarp \
            --rel \
            --ref=${OneSamplingFolder}/prevols/sli${znum}.nii.gz \
            --warp1=${GradientDistortionField} \
            --postmat=${OneSamplingFolder}/prevols/volslimatrix \
            --out=${OneSamplingFolder}/sli_gdc_warp${znum}.nii.gz

        # Store concatenate slicewise warp motion (in EPI space)
        SliceMergeSTRING+="${OneSamplingFolder}/sli_gdc_warp${znum}.nii.gz "   
    done

    # Merge sli_gdc to volume gdc warp 
    ${FSLDIR}/bin/fslmerge -z ${OneSamplingFolder}/MAT_${vnum}_all_warp.nii.gz $SliceMergeSTRING

    # Apply one-step warp, using spline interpolation
    ${FSLDIR}/bin/applywarp \
        --rel \
        --interp=spline \
        --in=${OneSamplingFolder}/prevols/vol${vnum}.nii.gz \
        --warp=${OneSamplingFolder}/MAT_${vnum}_all_warp.nii.gz \
        --ref=${OneSamplingFolder}/prevols/vol${vnum}.nii.gz \
        --out=${OneSamplingFolder}/postvols/vol${vnum}.nii.gz

    # Create strings for merging
    FrameMergeSTRING+="${OneSamplingFolder}/postvols/vol${vnum}.nii.gz " 

    #Do Basic Cleanup
    \rm -f ${OneSamplingFolder}/MAT_${vnum}_all_warp.nii.gz
done

echo "---> Merging results"
# Merge together results and restore the TR (saved beforehand)
${FSLDIR}/bin/fslmerge -tr ${OutputfMRI} $FrameMergeSTRING $tr

# Do Basic Cleanup
\rm -rf ${OneSamplingFolder}
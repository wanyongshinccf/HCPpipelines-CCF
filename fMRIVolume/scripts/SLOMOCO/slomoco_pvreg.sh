#!/bin/bash -e

#   Copyright (C) Cleveland Cllinic
#
#   SHCOPYRIGHT

Usage() {
    echo ""
    echo "Usage: slomoco_pv_reg.sh <4dinput> <4doutput> <MotionMatrixDir> <scout_image> <scount_image_mask>"
    echo ""
    exit
}

InputfMRIgdc=`${FSLDIR}/bin/remove_ext ${1}`
OutputfMRI=`${FSLDIR}/bin/remove_ext ${2}`
MotionMatrixDir=${3}
PartialVolumeFolder=${4}

TESTWS=0
if [ $TESTWS -gt 0 ]; then
fMRIFolder=/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL 
fMRIFolder=/home/shinw/HCP/100206/rfMRI_REST1_RL
InputfMRItdc=$fMRIFolder/rfMRI_REST1_RL_gdc
OutputfMRI=$fMRIFolder/SLOMOCO/epi_gdc_pv        
GradientDistortionField=${3}"$fMRIFolder"/rfMRI_REST1_RL_gdc_warp 
MotionMatrixDir=$fMRIFolder/MotionMatrices
PartialVolumeFolder="$fMRIFolder"/SLOMOCO/pv                 
fi

# generate inplane directory
if [ ! -d ${PartialVolumeFolder} ]; then
    echo mkdir -p ${PartialVolumeFolder}
    mkdir -p ${PartialVolumeFolder}
fi

## read dimensions
zdim=`fslval $InputfMRIgdc dim3`
tdim=`fslval $InputfMRIgdc dim4`
tr=`fslval $InputfMRIgdc pixdim4`

# generate mean volume of input
fslmaths $InputfMRIgdc -Tmean ${PartialVolumeFolder}/epimean
fslsplit $InputfMRIgdc ${PartialVolumeFolder}/vol  -t

# generate the reference images at each TR
str_tcombined=""
for ((t = 0 ; t < $tdim ; t++ )); 
do 
    let t_div10=$t/10
    t_div10_track=0
    if [ $t -eq 0 ]; then
        echo -ne "Generating MOTSIM data and resampling back at volume $t"
    elif [ ${t_div10} -gt ${t_div10_track} ]; then
        echo -ne "."
        t_div10_track=${t_div10}
    fi 

    vnum=`${FSLDIR}/bin/zeropad $t 4`

    fmat=${MotionMatrixDir}/MAT_${vnum}
    convert_xfm -omat ${PartialVolumeFolder}/bmat -inverse $fmat

    # generate MOTSIM
    flirt                                       \
        -in             ${PartialVolumeFolder}/vol${vnum}         \
        -ref            ${PartialVolumeFolder}/epimean        \
        -applyxfm -init ${PartialVolumeFolder}/bmat           \
        -out            ${PartialVolumeFolder}/motsim  \
        -interp         nearestneighbour
        
    # move back MOTSIM
    flirt                                       \
        -in             ${PartialVolumeFolder}/motsim         \
        -ref            ${PartialVolumeFolder}/epimean        \
        -applyxfm -init ${fmat}                 \
        -out            ${PartialVolumeFolder}/epipv${vnum}  \
        -interp         nearestneighbour

    str_tcombined="$str_tcombined ${PartialVolumeFolder}/epipv${vnum} "
done

# combine all the volumes
${FSLDIR}/bin/fslmerge -tr ${PartialVolumeFolder}/epipvall `echo $str_tcombined` $tr

# demean and normaliz
${FSLDIR}/bin/fslmaths ${PartialVolumeFolder}/epipvall -Tmean ${PartialVolumeFolder}/epipv_mean
${FSLDIR}/bin/fslmaths ${PartialVolumeFolder}/epipvall -Tstd  ${PartialVolumeFolder}/epipv_std 
${FSLDIR}/bin/fslmaths ${PartialVolumeFolder}/epipvall -sub ${PartialVolumeFolder}/epipv_mean -div ${PartialVolumeFolder}/epipv_std ${OutputfMRI}

# clean up
\rm -rf ${PartialVolumeFolder}
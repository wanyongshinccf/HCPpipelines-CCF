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
opts_SetScriptDescription "Run SLOMOCO for HCP pipeline"

opts_AddMandatory '--workingdir' 'SLOMOCOFolder' 'path' "working dir"

opts_AddMandatory '--fmriname' 'NameOffMRI' 'string' "fMRI study name"

opts_AddMandatory '--infmri' 'InputfMRI' 'file' "input fMRI time series (NIFTI)"

opts_AddMandatory '--infmrigdc' 'InputfMRIgdc' 'file' "input gradient distortion corrected fMRI time series (NIFTI)"

opts_AddMandatory '--outfmri' 'OutputfMRI' 'string' "'name (prefix) to use for the output"

opts_AddMandatory '--scoutin' 'ScoutInput' 'volume' "Used as the target"

opts_AddMandatory '--T1acpcbrainmask' 'T1acpcBrainMask' 'mask' "input FreeSurfer brain mask or nifti format in T1w space"

opts_AddMandatory '--owarp' 'fMRI2strOutputTransform' 'path' "output fMRI to T1w"

opts_AddMandatory '--motionmatdir' 'MotionMatrixFolder' 'path' "input motion correcton matrix directory"

opts_AddMandatory '--motionmatprefix' 'MotionMatrixPrefix' 'string' "input motion correcton matrix filename prefix"

opts_AddMandatory '--gdfield' 'GradientDistortionField' 'gradient' "input warpfield for gradient non-linearity correction"

opts_AddMandatory '--sliacqtimefile' 'SliAcqTimeFile' 'file' "slice acquisition timing file (s)"

opts_ParseArguments "$@"

#display the parsed/default values
opts_ShowValues

# --- Report arguments

verbose_echo "  "
verbose_red_echo " ===> Running SLOMOCO"
verbose_echo " "
verbose_echo " Using parameters ..."
verbose_echo "         --workingdir: ${SLOMOCOFolder}"
verbose_echo "           --fmriname: ${NameOffMRI}"
verbose_echo "             --infmri: ${InputfMRI}"
verbose_echo "          --infmrigdc: ${InputfMRIgdc}"
verbose_echo "            --outfmri: ${OutputfMRI}"
verbose_echo "            --scoutin: ${ScoutInput}"
verbose_echo "       --motionmatdir: ${MotionMatrixFolder}"
verbose_echo "    --motionmatprefix: ${MotionMatrixPrefix}"
verbose_echo "    --T1acpcbrainmask: ${T1acpcBrainMask}"
verbose_echo "              --owarp: ${fMRI2strOutputTransform}"
verbose_echo "            --gdfield: ${GradientDistortionField}"
verbose_echo "     --sliacqtimefile: ${SliAcqTimeFile}"
verbose_echo " "

TESTWS=0
if [ $TESTWS -gt 0 ]; then
fMRIFolder=/mnt/hcp01/WU_MINN_HCP/103010/rfMRI_REST1_RL
T1wFolder=/mnt/hcp01/WU_MINN_HCP/103010/T1w
SLOMOCOFolder="$fMRIFolder"/SLOMOCO 
NameOffMRI=rfMRI_REST1_RL
InputfMRI=$fMRIFolder/rfMRI_REST1_RL_orig
InputfMRIgdc=$fMRIFolder/rfMRI_REST1_RL_gdc
OutfMRI=$fMRIFolder/rfMRI_REST1_RL_slomoco         
ScoutInput=$fMRIFolder/Scout_orig
ScoutInputgdc=$fMRIFolder/Scout_gdc
T1acpcBrainMask=${T1wFolder}/brainmask_fs
fMRI2strOutputTransform=${T1wFolder}/xfms/rfMRI_REST1_RL2str
MotionMatrixFolder=$fMRIFolder/MotionMatrices
GradientDistortionField="$fMRIFolder"/rfMRI_REST1_RL_gdc_warp                
SliAcqTimeFile=/mnt/hcp01/SW/HCPpipelines-CCF/global/config/SliceAcqTime_3T_TR720ms.txt
fi

echo " "
echo " START: SLOMOCO HCP"
echo $SLOMOCOFolder
# Record the input options in a log file
echo "$0 $@" >> $SLOMOCOFolder/log.txt
echo "PWD = `pwd`" >> $SLOMOCOFolder/log.txt
echo "date: `date`" >> $SLOMOCOFolder/log.txt
echo " " >> $SLOMOCOFolder/log.txt

# define dir
InplaneMotinFolder="$SLOMOCOFolder/inplane"
OutofPlaneMotionFolder="$SLOMOCOFolder/outofplane"
PartialVolumeFolder="$SLOMOCOFolder/pv"

# define variable
InputfMRI_mask=$SLOMOCOFolder/"${NameOffMRI}"_mask
str2fMRIOutputTransform=$SLOMOCOFolder/str2"${NameOffMRI}"

# read tfile and calculate SMS factor  
SMSfactor=0
while IFS= read -r line; do
  # Process each line here
  #echo "Read line: $line"
  if [ $line == "0" ] || [ $line == "0.0" ] ; then
    let "SMSfactor+=1"
  fi
done < "$SliAcqTimeFile"
echo "inplane acceleration is $SMSfactor based on slice acquisition timing file."

# sanity check
zdim=`fslval $InputfMRI dim3`
if [ $SMSfactor == 0 ] ; then
    echo "ERROR: slice acquisition timing does not have zero"
    exit
elif [ $SMSfactor == $zdim ] ; then
    echo "ERROR: all slice acquisition timing was time-shifted to zero"
    exit
elif [ $SMSfactor != "8" ] ; then
    echo "Warning: SMS factor in 3T HCP is expected to be 8."
fi

# Snippped from OneStepSampling.sh
# needed for good mask in EPI space.
# Create a combined warp if nonlinear registration to reference is used

# Generate fMRI_mask (not scout mask) Just use Scout image to save time
${FSLDIR}/bin/invwarp -w ${fMRI2strOutputTransform}   \
    -o ${str2fMRIOutputTransform}    \
    -r ${ScoutInput}

${FSLDIR}/bin/applywarp --rel --interp=nn \
    -i ${T1acpcBrainMask} \
    -r ${ScoutInput} \
    -w ${str2fMRIOutputTransform} \
    -o ${InputfMRI_mask}

# inplane motion correction
# HCP version of run_correction_vol_slicemocoxy_afni.tcsh
echo "SLOMOCO STEP1: Inplane motion correction"
echo "               x-/y-shift and z-rotation motion is corrected."
$RUN "$SLOMOCODIR"/slomoco_inplane.sh    \
    ${InputfMRI}                         \
    ${SLOMOCOFolder}/epi_mocoxy          \
    ${ScoutInput}                         \
    ${InputfMRI_mask}                    \
    ${MotionMatrixFolder}                \
    ${SMSfactor}                         \
    ${InplaneMotinFolder}

# out-of-plane motion estimation (NOT CORRECTION)
# HCP version of run_correction_vol_slicemocoxy_afni.tcsh
echo "SLOMOCO STEP2: Out-of-plane motion estimation"
echo "               x-/y-rotation and z-shift motion is estimated."
$RUN "$SLOMOCODIR"/slomoco_outofplane.sh    \
    ${SLOMOCOFolder}/epi_mocoxy             \
    ${ScoutInput}                           \
    ${InputfMRI_mask}                      \
    ${MotionMatrixFolder}                   \
    ${SMSfactor}                            \
    ${OutofPlaneMotionFolder}

# combine in- and out-of-plane motion parameter
echo "SLOMOCO STEP3: Combine in-/out-of-plane motion parameters."
echo "               Will be used as slicewise motion nuisance regressors."
$RUN "$SLOMOCODIR"/slomoco_combine_mopa.sh  \
    ${InputfMRI}                            \
    ${SLOMOCOFolder}                        \
    ${InplaneMotinFolder}                   \
    ${OutofPlaneMotionFolder}               \
    ${SMSfactor}

# HCP version of gen_pvreg.tcsh
echo "SLOMOCO STEP4: Generate partial volume regressor." 
echo "               Will be used as voxelwise motion nuisance regressor."
$RUN "$SLOMOCODIR"/slomoco_pvreg.sh         \
    ${InputfMRIgdc}                         \
    ${SLOMOCOFolder}/epi_gdc_pv             \
    ${MotionMatrixFolder}                   \
    ${PartialVolumeFolder}

# onesampling in native space 
echo "SLOMOCO STEP5: Combine GDC and SLOMOCO motion correction."
echo "               Due to slicewise regressors in a native space,"
echo "               SLOMOCO is resampled first in native space with regress-out."
echo "               Then move to MNI space later again using slomoco_postsampling.sh"
$RUN "$SLOMOCODIR"/slomoco_presampling.sh   \
    ${InputfMRI}                            \
    ${SLOMOCOFolder}/epi_gdc_mocoxy         \
    ${GradientDistortionField}              \
    ${MotionMatrixFolder}                   \
    ${SLOMOCOFolder}                        \
    ${InplaneMotinFolder}                   \
    ${OutofPlaneMotionFolder}               \
    ${SMSfactor}

# clean up
# You might delete epi_gdc_mocoxy and epi_gdc_pv, if you don't need them.
rm -f ${SLOMOCOFolder}/epi_mocoxy* 
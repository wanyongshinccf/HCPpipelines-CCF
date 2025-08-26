#!/bin/bash 

get_batch_options() {
    local arguments=("$@")

    command_line_specified_study_folder=""
    command_line_specified_subj=""
    command_line_specified_local=""
    command_line_specified_run_local="FALSE"

    local index=0
    local numArgs=${#arguments[@]}
    local argument

    while [ ${index} -lt ${numArgs} ]; do
        argument=${arguments[index]}

        case ${argument} in
            --StudyFolder=*)
                command_line_specified_study_folder=${argument#*=}
                index=$(( index + 1 ))
                ;;
            --Subject=*)
                command_line_specified_subj=${argument#*=}
                index=$(( index + 1 ))
                ;;
            --local=*)
                command_line_specified_local=${argument#*=}
                index=$(( index + 1 ))
                ;;
            --task=*)
                command_line_specified_task=${argument#*=}
                index=$(( index + 1 ))
                ;;
            --step=*)
                command_line_specified_step=${argument#*=}
                index=$(( index + 1 ))
                ;;
            --runlocal)
                command_line_specified_run_local="TRUE"
                index=$(( index + 1 ))
                ;;
            *)
                echo ""
                echo "ERROR: Unrecognized Option: ${argument}"
                echo ""
                exit 1
                ;;
        esac
    done
}

get_batch_options "$@"

# modify the below to run the script in the multiple local machines.

if [ -n "${command_line_specified_local}" ]; then
    export localHCPhorse="${command_line_specified_local}"
else
    export localHCPhorse="linux"
fi

if [[ ${localHCPhorse} == "macws" ]]; then
    StudyFolder="/Volumes/MacExtDrive/work/HCP" #Location of Subject folders (named by subjectID) #W.S
    Subjlist="100206" #Space delimited list of subject IDs
    EnvironmentScriptDir="/Users/wanyongshin/SW/git/HCPpipelines-CCF/Scripts"
elif [[ ${localHCPhorse} == "linux" ]]; then
    StudyFolder="/mnt/hcp01/WU_MINN_HCP" #Location of Subject folders (named by subjectID) #W.S
    Subjlist="100206" #Space delimited list of subject IDs
    EnvironmentScriptDir="/mnt/hcp01/SW/HCPpipelines-CCF/Scripts"
elif [[ ${localHCPhorse} == "ideapc" ]]; then
    StudyFolder="/home/shinw/HCP" #Location of Subject folders (named by subjectID) #W.S
    Subjlist="100206" #Space delimited list of subject IDs
    EnvironmentScriptDir="/home/shinw/SW/HCPpipelines-CCF/Scripts"    
fi
EnvironmentScript="${EnvironmentScriptDir}/SetUpHCPPipeline.sh" #Pipeline environment script

if [ -n "${command_line_specified_study_folder}" ]; then
    StudyFolder="${command_line_specified_study_folder}"
fi

if [ -n "${command_line_specified_subj}" ]; then
    Subjlist="${command_line_specified_subj}"
fi

# Requirements for this script
#  installed versions of: FSL, FreeSurfer, Connectome Workbench (wb_command), gradunwarp (HCP version)
#  environment: HCPPIPEDIR, FSLDIR, FREESURFER_HOME, CARET7DIR, PATH for gradient_unwarp.py

#Set up pipeline environment variables and software
source "$EnvironmentScript"

# Log the originating call
echo "$@"

#NOTE: syntax for QUEUE has changed compared to earlier pipeline releases,
#DO NOT include "-q " at the beginning
#default to no queue, implying run local
QUEUE=""
#QUEUE="hcp_priority.q"

if [[ -n $HCPPIPEDEBUG ]]
then
    set -x
fi


########################################## INPUTS ########################################## 

# Scripts called by this script do NOT assume anything about the form of the input names or paths.
# This batch script assumes the HCP raw data naming convention.
#
# For example, if phase encoding directions are LR and RL, for tfMRI_EMOTION_LR and tfMRI_EMOTION_RL:
#
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_LR/${Subject}_3T_tfMRI_EMOTION_LR.nii.gz
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_LR/${Subject}_3T_tfMRI_EMOTION_LR_SBRef.nii.gz
#
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_RL/${Subject}_3T_tfMRI_EMOTION_RL.nii.gz
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_RL/${Subject}_3T_tfMRI_EMOTION_RL_SBRef.nii.gz
#
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_LR/${Subject}_3T_SpinEchoFieldMap_LR.nii.gz
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_LR/${Subject}_3T_SpinEchoFieldMap_RL.nii.gz
#
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_RL/${Subject}_3T_SpinEchoFieldMap_LR.nii.gz
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_RL/${Subject}_3T_SpinEchoFieldMap_RL.nii.gz
#
# If phase encoding directions are PA and AP:
#
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_PA/${Subject}_3T_tfMRI_EMOTION_PA.nii.gz
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_PA/${Subject}_3T_tfMRI_EMOTION_PA_SBRef.nii.gz
#
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_AP/${Subject}_3T_tfMRI_EMOTION_AP.nii.gz
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_AP/${Subject}_3T_tfMRI_EMOTION_AP_SBRef.nii.gz
#
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_PA/${Subject}_3T_SpinEchoFieldMap_PA.nii.gz
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_PA/${Subject}_3T_SpinEchoFieldMap_AP.nii.gz
#
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_AP/${Subject}_3T_SpinEchoFieldMap_PA.nii.gz
#   ${StudyFolder}/${Subject}/unprocessed/3T/tfMRI_EMOTION_AP/${Subject}_3T_SpinEchoFieldMap_AP.nii.gz
#
#
# Change Scan Settings: EchoSpacing, FieldMap DeltaTE (if not using TOPUP),
# and $TaskList to match your acquisitions
#
# If using gradient distortion correction, use the coefficents from your scanner.
# The HCP gradient distortion coefficents are only available through Siemens.
# Gradient distortion in standard scanners like the Trio is much less than for the HCP 'Connectom' scanner.
#
# To get accurate EPI distortion correction with TOPUP, the phase encoding direction
# encoded as part of the ${TaskList} name must accurately reflect the PE direction of
# the EPI scan, and you must have used the correct images in the
# SpinEchoPhaseEncode{Negative,Positive} variables.  If the distortion is twice as
# bad as in the original images, either swap the
# SpinEchoPhaseEncode{Negative,Positive} definition or reverse the polarity in the
# logic for setting UnwarpDir.
# NOTE: The pipeline expects you to have used the same phase encoding axis and echo
# spacing in the fMRI data as in the spin echo field map acquisitions.

######################################### DO WORK ##########################################

SCRIPT_NAME=`basename "$0"`
echo $SCRIPT_NAME

if [ -n "${command_line_specified_task}" ]; then
    TaskList=${command_line_specified_task}
else
    TaskList=()
    TaskList+=(rfMRI_REST1_RL)
    TaskList+=(rfMRI_REST1_LR)
    #TaskList+=(rfMRI_REST2_RL)
    #TaskList+=(rfMRI_REST2_LR)
fi

STEP=()
if [ -n "${command_line_specified_step}" ]; then
    for s in "${command_line_specified_step[@]}" ; 
    do 
        echo $s
        STEP+=($s)
    done
else
    STEP="all"
fi

# Start or launch pipeline processing for each subject
for Subject in $Subjlist ; do
    echo "${SCRIPT_NAME}: Processing Subject: ${Subject}"

    for fMRIName in "${TaskList[@]}" ; do
        echo "  ${SCRIPT_NAME}: Processing Scan: ${fMRIName}"

        TaskName=`echo ${fMRIName} | sed 's/_[APLR]\+$//'`
        echo "  ${SCRIPT_NAME}: TaskName: ${TaskName}"

        len=${#fMRIName}
        echo "  ${SCRIPT_NAME}: len: $len"
        start=$(( len - 2 ))

        PhaseEncodingDir=${fMRIName:start:2}
        echo "  ${SCRIPT_NAME}: PhaseEncodingDir: ${PhaseEncodingDir}"

        case ${PhaseEncodingDir} in
            "PA")
                UnwarpDir="y"
                ;;
            "AP")
                UnwarpDir="y-"
                ;;
            "RL")
                UnwarpDir="x"
                ;;
            "LR")
                UnwarpDir="x-"
                ;;
            *)
                echo "${SCRIPT_NAME}: Unrecognized Phase Encoding Direction: ${PhaseEncodingDir}"
                exit 1
                ;;
        esac

        echo "  ${SCRIPT_NAME}: UnwarpDir: ${UnwarpDir}"

        fMRITimeSeries="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_${fMRIName}.nii.gz"

        # A single band reference image (SBRef) is recommended if available
        # Set to NONE if you want to use the first volume of the timeseries for motion correction
        fMRISBRef="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_${fMRIName}_SBRef.nii.gz"

        # "Effective" Echo Spacing of fMRI image (specified in *sec* for the fMRI processing)
        # EchoSpacing = 1/(BWPPPE * ReconMatrixPE)
        #   where BWPPPE is the "BandwidthPerPixelPhaseEncode" = DICOM field (0019,1028) for Siemens, and
        #   ReconMatrixPE = size of the reconstructed image in the PE dimension
        # In-plane acceleration, phase oversampling, phase resolution, phase field-of-view, and interpolation
        # all potentially need to be accounted for (which they are in Siemen's reported BWPPPE)
        EchoSpacing="0.00058" 

        # Susceptibility distortion correction method (required for accurate processing)
        # Values: TOPUP, SiemensFieldMap (same as FIELDMAP), GEHealthCareLegacyFieldMap, GEHealthCareFieldMap, PhilipsFieldMap
        DistortionCorrection="TOPUP"

        # Receive coil bias field correction method
        # Values: NONE, LEGACY, or SEBASED
        #   SEBASED calculates bias field from spin echo images (which requires TOPUP distortion correction)
        #   LEGACY uses the T1w bias field (method used for 3T HCP-YA data, but non-optimal; no longer recommended).
        BiasCorrection="SEBASED"

        # For the spin echo field map volume with a 'negative' phase encoding direction
        # (LR in HCP-YA data; AP in 7T HCP-YA and HCP-D/A data)
        # Set to NONE if using regular FIELDMAP
        SpinEchoPhaseEncodeNegative="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_SpinEchoFieldMap_LR.nii.gz"

        # For the spin echo field map volume with a 'positive' phase encoding direction
        # (RL in HCP-YA data; PA in 7T HCP-YA and HCP-D/A data)
        # Set to NONE if using regular FIELDMAP
        SpinEchoPhaseEncodePositive="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_SpinEchoFieldMap_RL.nii.gz"

        # Topup configuration file (if using TOPUP)
        # Set to NONE if using regular FIELDMAP
        TopUpConfig="${HCPPIPEDIR_Config}/b02b0.cnf"

        # Not using Siemens Gradient Echo Field Maps for susceptibility distortion correction
        # Set following to NONE if using TOPUP
        # or set the following inputs if using regular FIELDMAP (i.e. SiemensFieldMap GEHealthCareFieldMap PhilipsFieldMap)
        MagnitudeInputName="NONE" #Expects 4D Magnitude volume with two 3D volumes (differing echo times) - or a single 3D Volume
        PhaseInputName="NONE" #Expects a 3D Phase difference volume (Siemen's style) -or Fieldmap in Hertz for GE Healthcare
        DeltaTE="NONE" #For Siemens, typically 2.46ms for 3T, 1.02ms for 7T; For GE Healthcare at 3T, *usually* 2.304ms for 2D-B0MAP and 2.272ms for 3D-B0MAP
        # For GE HealthCare, see related notes in PreFreeSurferPipelineBatch.sh and FieldMapProcessingAll.sh

        # Path to GE HealthCare Legacy style B0 fieldmap with two volumes
        #   1. field map in hertz
        #   2. magnitude image
        # Set to "NONE" if not using "GEHealthCareLegacyFieldMap" as the value for the DistortionCorrection variable
        #
        # Example Value: 
        #  GEB0InputName="${StudyFolder}/${Subject}/unprocessed/3T/${fMRIName}/${Subject}_3T_GradientEchoFieldMap.nii.gz" 
        #  DeltaTE=2.272 # ms 
        GEB0InputName="NONE"

        # Target final resolution of fMRI data
        # 2mm is recommended for 3T HCP data, 1.6mm for 7T HCP data (i.e. should match acquisition resolution)
        # Use 2.0 or 1.0 to avoid standard FSL templates
        FinalFMRIResolution="2"

        # Gradient distortion correction
        # Set to NONE to skip gradient distortion correction
        # (These files are considered proprietary and therefore not provided as part of the HCP Pipelines -- contact Siemens to obtain)
        GradientDistortionCoeffs="${HCPPIPEDIR_Config}/coeff_SC72C_Skyra.grad"

        # Type of motion correction
        # Values: MCFLIRT (default), FLIRT
        # (3T HCP-YA processing used 'FLIRT', but 'MCFLIRT' now recommended)
        MCType="MCFLIRT"

        if [[ "${command_line_specified_run_local}" == "TRUE" || "$QUEUE" == "" ]] ; then
            echo "About to locally run ${HCPHCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.ccf.sh"
            queuing_command=("$HCPPIPEDIR"/global/scripts/captureoutput.sh)
        else
            echo "About to use fsl_sub to queue ${HCPPIPEDIR}/fMRIVolume/GenericfMRIVolumeProcessingPipeline.ccf.sh"
            queuing_command=("$FSLDIR/bin/fsl_sub" -q "$QUEUE")
        fi

        for step in "${STEP[$]}"
            "${queuing_command[@]}" "$HCPCCFPIPEDIR"/fMRIVolume/GenericfMRIVolumeProcessingPipeline.ccf.sh \
            --path="$StudyFolder" \
            --subject="$Subject" \
            --fmriname="$fMRIName" \
            --fmritcs="$fMRITimeSeries" \
            --fmriscout="$fMRISBRef" \
            --SEPhaseNeg="$SpinEchoPhaseEncodeNegative" \
            --SEPhasePos="$SpinEchoPhaseEncodePositive" \
            --fmapmag="$MagnitudeInputName" \
            --fmapphase="$PhaseInputName" \
            --fmapcombined="$GEB0InputName" \
            --echospacing="$EchoSpacing" \
            --echodiff="$DeltaTE" \
            --unwarpdir="$UnwarpDir" \
            --fmrires="$FinalFMRIResolution" \
            --dcmethod="$DistortionCorrection" \
            --gdcoeffs="$GradientDistortionCoeffs" \
            --topupconfig="$TopUpConfig" \
            --biascorrection="$BiasCorrection" \
            --mctype="$MCType" \
            --step="$step"

            # The following lines are used for interactive debugging to set the positional parameters: $1 $2 $3 ...

            echo "set -- --path=$StudyFolder \
            --subject=$Subject \
            --fmriname=$fMRIName \
            --fmritcs=$fMRITimeSeries \
            --fmriscout=$fMRISBRef \
            --SEPhaseNeg=$SpinEchoPhaseEncodeNegative \
            --SEPhasePos=$SpinEchoPhaseEncodePositive \
            --fmapmag=$MagnitudeInputName \
            --fmapphase=$PhaseInputName \
            --fmapcombined=$GEB0InputName \
            --echospacing=$EchoSpacing \
            --echodiff=$DeltaTE \
            --unwarpdir=$UnwarpDir \
            --fmrires=$FinalFMRIResolution \
            --dcmethod=$DistortionCorrection \
            --gdcoeffs=$GradientDistortionCoeffs \
            --topupconfig=$TopUpConfig \
            --biascorrection=$BiasCorrection \
            --mctype=$MCType" \
            --step="$step"

            echo ". ${EnvironmentScript}"
        done
    done
done

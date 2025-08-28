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

input=`${FSLDIR}/bin/remove_ext ${1}`
output=`${FSLDIR}/bin/remove_ext ${2}`
base=`${FSLDIR}/bin/remove_ext ${3}`
mask=`${FSLDIR}/bin/remove_ext ${4}`
MotionMatrixDir=${5} #MotionMatrices
SMSfactor=${6}
inplanedir=${7}

# test purpose, will be deleted
# workdir="SLOMOCO"
#inplanedir=$workdir/inplane
#wpath="/Volumes/MacExtDrive/work/HCP/100206/rfMRI_REST1_RL"
#input=$wpath/rfMRI_REST1_RL_gdc
#output=$wpath/rfMRI_REST1_RL_gdc_slomoco
#base=$wpath/Scout_gdc
#mask=$wpath/Scout_gdc_mask
#MotionMatrixDir=$wpath/MotionMatrices
#SMSfactor=8

# generate inplane directory
if [ ! -d ${inplanedir} ]; then
    mkdir -p ${inplanedir}
fi

# read dimensions
zdim=`fslval $input dim3`
tdim=`fslval $input dim4`
tr=`fslval $input pixdim4`
let "zmbdim=$zdim/$SMSfactor"

# generate each volume of input
fslsplit $input ${inplanedir}/epivol  -t

# generate the reference images at each TR
str_tcombined=""
t_div10_track=0
let "t_last=tdim-1"
for ((t = 0 ; t < $tdim ; t++ )); 
do 
    let "t_div10=$t/10" || true
    if [ $t -eq 0 ]; then
        echo -ne "Running inplane motion correction at volume ${t}.."
    elif [ $t -eq ${t_last} ]; then
        echo "done."
    fi 
    
    fmat=${MotionMatrixDir}/MAT_`printf %04d $t`
    convert_xfm -omat $inplanedir/bmat -inverse $fmat
    flirt                                           \
        -in ${base}                                 \
        -ref ${inplanedir}/epivol0000              \
        -applyxfm -init $inplanedir/bmat            \
        -out ${inplanedir}/refvol   \
        -interp nearestneighbour

    # generate each slice of input
    fslsplit ${inplanedir}/epivol`printf %04d $t`   \
        ${inplanedir}/episli -z
    fslsplit ${inplanedir}/refvol   \
        ${inplanedir}/refsli -z

    for ((zmb = 0 ; zmb < $zmbdim ; zmb++ )); 
    do
        str_ref=""
        str_epi=""
        for ((mb = 0 ; mb < $SMSfactor ; mb++ ));
        do
            let "k=$mb*$zmbdim+$zmb" || true
            str_ref="$str_ref ${inplanedir}/refsli`printf %04d $k` "
            str_epi="$str_epi ${inplanedir}/episli`printf %04d $k` "
        done

        fslmerge -z ${inplanedir}/refSMSsli `echo $str_ref`
        fslmerge -z ${inplanedir}/epiSMSsli `echo $str_epi`
        
        # note that weight or mask is not used while original SLOMOCO uses them
        # need to investigate their effect throughly later
        flirt                                                                           \
            -in     ${inplanedir}/epiSMSsli                                             \
            -ref    ${inplanedir}/refSMSsli                                             \
            -out    ${inplanedir}/epiSMSsli_mc                                          \
            -omat   ${inplanedir}/epiSMSsli_mc_mat_z`printf %04d $zmb`_t`printf %04d $t` \
            -schedule ${FSLDIR}/etc/flirtsch/sch2D_3dof                                 \
            -interp nearestneighbour

        # split slices 
        fslsplit ${inplanedir}/epiSMSsli_mc ${inplanedir}/__temp -z

        # renames slices
        for ((mb = 0 ; mb < $SMSfactor ; mb++ ));
        do
            let "k=$mb*$zmbdim+$zmb" || true
            ${FSLDIR}/bin/immv ${inplanedir}/__temp`printf %04d $mb`  ${inplanedir}/episli_mc`printf %04d $k`
        done
    done # zmb loop ends

    # combine all the slices at t
    str_zcombined=""
    for ((z = 0 ; z < $zdim ; z++ )); 
    do
        str_zcombined="$str_zcombined ${inplanedir}/episli_mc`printf %04d $z` "
    done
    fslmerge -z ${inplanedir}/epivol_mc`printf %04d $t` ${str_zcombined}
    str_tcombined="$str_tcombined ${inplanedir}/epivol_mc`printf %04d $t` "
done

# combine all the volumes
${FSLDIR}/bin/fslmerge -tr ${inplanedir}/epi_mc `echo $str_tcombined` $tr
${FSLDIR}/bin/immv ${inplanedir}/epi_mc ${output}

# convert matrix to motion parameters, snipping from mcflirt.sh
echo "Saving inplane motion parameters"
echo "Removing pre-existing motion files"
\rm -f ${inplanedir}/mopa_*par
pi=$(echo "scale=10; 4*a(1)" | bc -l)
for ((zmb = 0 ; zmb < $zmbdim ; zmb++ )); 
do
    for ((t = 0 ; t < $tdim ; t++ )); 
    do
        tmat="${inplanedir}/epiSMSsli_mc_mat_z`printf %04d $zmb`_t`printf %04d $t`"
        mm=`${FSLDIR}/bin/avscale --allparams $tmat $base | grep "Translations" | awk '{print $5 " " $6 " " $7}'`
        mmx=`echo $mm | cut -d " " -f 1`
        mmy=`echo $mm | cut -d " " -f 2`
        mmz=`echo $mm | cut -d " " -f 3`
        radians=`${FSLDIR}/bin/avscale --allparams $tmat $base | grep "Rotation Angles" | awk '{print $6 " " $7 " " $8}'`
        radx=`echo $radians | cut -d " " -f 1`
        degx=`echo "$radx * (180 / $pi)" | sed 's/[eE]+\?/*10^/g' | bc -l`
        rady=`echo $radians | cut -d " " -f 2`
        degy=`echo "$rady * (180 / $pi)" | sed 's/[eE]+\?/*10^/g' | bc -l`
        radz=`echo $radians | cut -d " " -f 3`
        degz=`echo "$radz * (180 / $pi)" | sed 's/[eE]+\?/*10^/g' | bc -l`
        echo `printf "%.6f" $mmx` `printf "%.6f" $mmy` `printf "%.6f" $mmz` `printf "%.6f" $degx` `printf "%.6f" $degy` `printf "%.6f" $degz` >> ${inplanedir}/mopa_z`printf %04d $zmb`.par
    
        # convert flirt mat format to mcflirt mat format 
        # later after onesampling 
    done
done

# temporary save mat files here
echo "mkdir -p ${inplanedir}/MAT"
mkdir -p ${inplanedir}/MAT
echo "mv ${inplanedir}/epiSMSsli_mc_mat_z* ${inplanedir}/MAT"
mv ${inplanedir}/epiSMSsli_mc_mat_z* ${inplanedir}/MAT
echo "inplane motion parameters are saved."

# cleanup
\rm -f  ${inplanedir}/ref* \
        ${inplanedir}/bmat \
        ${inplanedir}/epi* \
        



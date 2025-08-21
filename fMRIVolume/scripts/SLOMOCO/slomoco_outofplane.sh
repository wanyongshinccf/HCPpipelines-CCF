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
base=`${FSLDIR}/bin/remove_ext ${2}`
mask=`${FSLDIR}/bin/remove_ext ${3}`
MotionMatrixDir=${4} #MotionMatrices
SMSfactor=${5}
outofplanedir=${6}

# test purpose, will be deleted
#wpath="/Volumes/MacExtDrive/work/HCP/100206/rfMRI_REST1_RL"
#input=$wpath/rfMRI_REST1_RL_gdc_slomoco
#base=$wpath/Scout_gdc
#mask=$wpath/Scout_gdc_mask
#MotionMatrixDir=$wpath/MotionMatrices
#SMSfactor=8
#workdir=$wpath/"SLOMOCO"
#outofplanedir=$workdir/outofplane

# generate inplane directory
if [ ! -d ${workdir} ]; then
    mkdir -p ${workdir}
fi
if [ ! -d ${outofplanedir} ]; then
    mkdir -p ${outofplanedir}
fi

# read dimensions
zdim=`fslval $input dim3`
tdim=`fslval $input dim4`
let "zmbdim=$zdim/$SMSfactor"

# temporal mean; reference from moco mean or scout?
fslmaths $input -Tmean ${outofplanedir}/ref

# concatenate
str_conca=""
for ((t = 0 ; t < $tdim ; t++ )); 
do 
    str_conca="$str_conca ${outofplanedir}/ref "
done
fslmerge -t ${outofplanedir}/ref_tseries  `echo $str_conca` 

# spilit ref timeseries at z
fslsplit ${outofplanedir}/ref_tseries ${outofplanedir}/ref_tseries_z -z

# spilit epi_slomoco timeseries at z
fslsplit ${input} ${outofplanedir}/epislomoco_z -z

# generates epi z t-series
for ((zmb = 0 ; zmb < $zmbdim ; zmb++ ));
do
    echo "Estimating out-of-plane motion at $zmb of $zmbdim time-series slice."
    str_conca=""
    for ((z = 0 ; z < $zdim ; z++ )); 
    do
        r=$(($z%$SMSfactor))
        if [ $r == $zmb ]; then
            str_conca="$str_conca ${outofplanedir}/epislomoco_z`printf %04d $zmb` "
        else
            str_conca="$str_conca ${outofplanedir}/ref_tseries_z`printf %04d $zmb` "
        fi
    done
    fslmerge -z ${outofplanedir}/epislomoco_syn_z`printf %04d $zmb` `echo $str_conca`

    mcflirt         \
        -in ${outofplanedir}/epislomoco_syn_z`printf %04d $zmb` \
        -r ${outofplanedir}/ref \
        -mats \
        -plots 
done

# sort out out of plane motion only, demean
# par file stored in this order
# first axis (x-) rot, second (y-)rot, the third z-rot (radian), x-shift, y-shift and z-shift (mm)
# unlike AFIN convention, axis is defined in the matrix, not in RAI 
echo "Saving out-of-plane motion parameters"
echo "Removing pre-existing motion files"
\rm -f ${outofplanedir}/mopa*par
pi=$(echo "scale=10; 4*a(1)" | bc -l)
for ((zmb = 0 ; zmb < $zmbdim ; zmb++ )); 
do
    for ((t = 0 ; t < $tdim ; t++ )); 
    do
        tmat="${outofplanedir}/epislomoco_syn_z`printf %04d $mb`_mcf.mat/MAT_`printf %04d $t`"
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
        echo `printf "%.6f" $mmx` `printf "%.6f" $mmy` `printf "%.6f" $mmz` `printf "%.6f" $degx` `printf "%.6f" $degy` `printf "%.6f" $degz` >> ${outofplanedir}/mopa_z`printf %04d $zmb`.par
    done
done

# cleanup
\rm -rf ${outofplanedir}/__tmp* \
        ${outofplanedir}/ref*   \
        ${outofplanedir}/epi* 
        
        




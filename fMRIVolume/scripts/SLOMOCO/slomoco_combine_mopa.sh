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
slomocodir=${2}
inplanedir=${3}
outofplanedir=${4}
SMSfactor=${5}

# test purpose, will be deleted
#wpath="/Volumes/MacExtDrive/work/HCP/100206/rfMRI_REST1_RL"
#input=$wpath/rfMRI_REST1_RL_gdc_slomoco
#slomocodir=$wpath/"SLOMOCO"
#inplanedir=$slomocodir/inplane
#outofplanedir=$slomocodir/outofplane
#SMSfactor=8

# read dimensions
zdim=`fslval $input dim3`
tdim=`fslval $input dim4`
let "zmbdim=${zdim}/${SMSfactor}"

# order: x-shift, y-shift, z-shift, x-rot, yrot, zrot
str_conca=""
for ((z = 0 ; z < $zdim ; z++ )); 
do
    zmb=$(($z%$SMSfactor))
    inpar="${inplanedir}/mopa_z`printf %04d $zmb`.par"
    outpar="${outofplanedir}/mopa_z`printf %04d $zmb`.par"

    cat $inpar | cut -d " " -f 1 > ${slomocodir}/xmm.1D
    cat $inpar | cut -d " " -f 2 > ${slomocodir}/ymm.1D
    cat $outpar | cut -d " " -f 3 > ${slomocodir}/zmm.1D
    cat $outpar | cut -d " " -f 4 > ${slomocodir}/xrad.1D
    cat $outpar | cut -d " " -f 5 > ${slomocodir}/yrad.1D
    cat $inpar | cut -d " " -f 6 > ${slomocodir}/zrad.1D
    
    paste ${slomocodir}/xmm.1D ${slomocodir}/ymm.1D ${slomocodir}/zmm.1D ${slomocodir}/xrad.1D ${slomocodir}/yrad.1D ${slomocodir}/zrad.1D > ${slomocodir}/slimopa_z`printf %04d $z`.1D
    str_conca="$str_conca ${slomocodir}/slimopa_z`printf %04d $z`.1D"
    #paste ${slomocodir}/xmm.1D ${slomocodir}/ymm.1D ${slomocodir}/zmm.1D ${slomocodir}/xrad.1D ${slomocodir}/yrad.1D ${slomocodir}/zrad.1D > ${slomocodir}/rm.slimopa.1D
    #paste ${slomocodir}/rm.slimopa.1D >> ${slomocodir}/slimopa.1D
done
paste `echo $str_conca` > ${slomocodir}/slimopa.1D


# cleanup
\rm -rf ${slomocodir}/*mm.1D    \
        ${slomocodir}/*rad.1D   \
        ${slomocodir}/slimopa_z*.1D  
        
        




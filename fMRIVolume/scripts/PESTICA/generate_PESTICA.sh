#!/Users/wanyongshin/fsl/bin/

InputfMRI=${1}
MaskfMRI=${2}
fMRIFolder=${3}
PhysioFolder=${3}
OutputFolder=${4}
SMSFactor=${5}

TESTWS=1
if [ $TESTWS -gt 0 ];
    fMRIFolder=/Volumes/MacExtDrive/work/HCP/100206/rfMRI_REST1_RL
    InputfMRI=${fMRIFolder}/rfMRI_REST1_RL_orig
    MaskfMRI=$fMRIFolder/SLOMOCO/Scout_orig_mask
    PhysioFolder=${fMRIFolder}/Physio    
    OutputFolder=${fMRIFolder}/PESTICAdev
    SMSFactor=8
fi

# make folder  
\mkdir -p ${OutputFolder}

# read dimensions
zdim=`fslval $InputfMRI dim3`
tdim=`fslval $InputfMRI dim4`
tr=`fslval $InputfMRI pixdim4`
let "zmbdim=$zdim/$SMSFactor"

# AFNI
if [ $FSLOUTPUTTYPE == "NIFTI_GZ" ]; then
    AFNIINPUTPOSTFIX="nii.gz"
elif [ $FSLOUTPUTTYPE == "NIFTI" ]; then
    AFNIINPUTPOSTFIX="nii"
fi

# step 1: generate coefficient map of cardiac and respiratory response function
3dDeconvolve -polort A \
    -input  ${InputfMRI}.$AFNIINPUTPOSTFIX \
    -x1D    ${OutputFolder}/__rm.polort.1D \
    -x1D_stop 
1d_tool.py -demean \
    -infile ${PhysioFolder}/RetroTS.PMU.card.slibase.1D \
    -write  ${OutputFolder}/__rm.card.demean.1D 
1d_tool.py -demean \
    -infile ${PhysioFolder}/RetroTS.PMU.resp.slibase.1D \
    -write  ${OutputFolder}/__rm.resp.demean.1D 

# step1: calculate coefficient map fromardiac/respiratory response function
# regress out all nuisances here
3dREMLfit               \
    -input      ${InputfMRI}.${AFNIINPUTPOSTFIX}   \
    -mask       ${MaskfMRI}.${AFNIINPUTPOSTFIX} \
    -matrix     ${OutputFolder}/__rm.polort.1D \
    -Oerrts     ${OutputFolder}/errts.polort.${AFNIINPUTPOSTFIX}  \
    -GOFORIT -overwrite       
3dREMLfit               \
    -input      ${InputfMRI}.${AFNIINPUTPOSTFIX}   \
    -matrix     ${OutputFolder}/__rm.polort.1D \
    -slibase_sm ${OutputFolder}/__rm.card.demean.1D \
    -Oerrts     ${OutputFolder}/errts.card.${AFNIINPUTPOSTFIX}  \
    -Obeta      ${OutputFolder}/beta.card.${AFNIINPUTPOSTFIX}  \
    -GOFORIT -overwrite       
3dREMLfit               \
    -input      ${InputfMRI}.${AFNIINPUTPOSTFIX}   \
    -matrix     ${OutputFolder}/__rm.polort.1D \
    -slibase_sm ${OutputFolder}/__rm.resp.demean.1D \
    -Oerrts     ${OutputFolder}/errts.resp.${AFNIINPUTPOSTFIX}  \
    -Obeta      ${OutputFolder}/beta.resp.${AFNIINPUTPOSTFIX}  \
    -GOFORIT -overwrite  

# calculate SOS reduction
3dTstat -SOS \
    -mask       ${MaskfMRI}.${AFNIINPUTPOSTFIX} \
    -prefix ${OutputFolder}/SOS.polort.${AFNIINPUTPOSTFIX} \
    ${OutputFolder}/errts.polort.${AFNIINPUTPOSTFIX}
3dTstat -SOS \
    -mask       ${MaskfMRI}.${AFNIINPUTPOSTFIX} \
    -prefix ${OutputFolder}/SOS.card.${AFNIINPUTPOSTFIX} \
    ${OutputFolder}/errts.card.${AFNIINPUTPOSTFIX}
3dTstat -SOS \
    -mask       ${MaskfMRI}.${AFNIINPUTPOSTFIX} \
    -prefix ${OutputFolder}/SOS.resp.${AFNIINPUTPOSTFIX} \
    ${OutputFolder}/errts.resp.${AFNIINPUTPOSTFIX}

3dcalc \
    -a ${OutputFolder}/SOS.polort.${AFNIINPUTPOSTFIX} \
    -b ${OutputFolder}/SOS.card.${AFNIINPUTPOSTFIX} \
    -c ${MaskfMRI}.${AFNIINPUTPOSTFIX} \
    -expr "(a-b)/a*step(c)/4*${tdim}" \
    -prefix ${OutputFolder}/Fmap.card.${AFNIINPUTPOSTFIX} 

3dcalc \
    -a ${OutputFolder}/SOS.polort.${AFNIINPUTPOSTFIX} \
    -b ${OutputFolder}/SOS.resp.${AFNIINPUTPOSTFIX} \
    -c ${MaskfMRI}.${AFNIINPUTPOSTFIX} \
    -expr "(a-b)/a*step(c)/4*${tdim}" \
    -prefix ${OutputFolder}/Fmap.resp.${AFNIINPUTPOSTFIX} 

# stat info embeded
3drefit -fbuc           ${OutputFolder}/Fmap.ard.${AFNIINPUTPOSTFIX} 
3drefit -sublabel   0   Card_Fstst ${OutputFolder}/Fmap.card.${AFNIINPUTPOSTFIX} 
3drefit -substatpar 0   fift 4 $tdim ${OutputFolder}/Fmap.card.${AFNIINPUTPOSTFIX} 
3drefit -fbuc           ${OutputFolder}/Fmap.resp.${AFNIINPUTPOSTFIX} 
3drefit -sublabel   0   Card_Fstst ${OutputFolder}/Fmap.resp.${AFNIINPUTPOSTFIX} 
3drefit -substatpar 0   fift 4 $tdim ${OutputFolder}/Fmap.resp.${AFNIINPUTPOSTFIX} 

# find fvalue with p < 0.001
fthr=`p2dsetstat -inset ${OutputFolder}/Fmap.card.${AFNIINPUTPOSTFIX} -pval 0.001 -2sided -quiet`

# find fmap ROI
3dcalc -a ${OutputFolder}/Fmap.card.${AFNIINPUTPOSTFIX} \
-expr "step(a-$fthr)" \
-prefix ${OutputFolder}/Fmap.card.roi.${AFNIINPUTPOSTFIX}

3dcalc -a ${OutputFolder}/Fmap.resp.${AFNIINPUTPOSTFIX} \
-expr "step(a-$fthr)" \
-prefix ${OutputFolder}/Fmap.resp.roi.${AFNIINPUTPOSTFIX}

# find resp function in high fmap and generate beta map using matlab 



# rerun RETROICOR
# ICA
# split each slice of time-series
fslsplit $fMRIFolder/$InputfMRI $fMRIFolder/$OutputFolder/${InputfMRI}_z -z
OptICASMS=1
if [ $OptICASMS -gt 0 ]; then
    for ((zmb = 0 ; zmb < $zmbdim ; zmb++ )); 
    do
        zmbnum=`printf %04d $zmb`
        str_conca=""    
        for ((mb = 0 ; mb < $SMSFactor ; mb++ ));
        do
            let "k=$mb*$zmbdim+$zmb" || true
            znum=`printf %04d $k`
            zslice=$fMRIFolder/$OutputFolder/${InputfMRI}_z${znum}
            str_conca="$str_conca ${zslice} "
        done
        fslmerge -z  $fMRIFolder/$OutputFolder/${InputfMRI}_SMS${zmbnum} ${str_conca}
        melodic -i $fMRIFolder/$OutputFolder/${InputfMRI}_SMS${zmbnum} \
            -o $fMRIFolder/$OutputFolder/${InputfMRI}_SMS${zmbnum}_ica \
            --nobet --report --Oall --tr=${tr}

    done
else
    for ((z = 0 ; z < $zdim ; z++ )); 
    do
        zmbnum=`printf %04d $z`
        melodic -i $fMRIFolder/$OutputFolder/${InputfMRI}_${zmbnum} \
            -o $fMRIFolder/$OutputFolder/${InputfMRI}_${zmbnum}_ica \
            --nobet --report --Oall --tr=${tr}
done

# step2 compare with RETROICOR
3dREMLf


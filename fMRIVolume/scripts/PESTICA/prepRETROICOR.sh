#!/bin/bash -e

#   Copyright (C) Cleveland Cllinic
#
#   SHCOPYRIGHT

Usage() {
    echo ""
    echo "Usage: prepRETROICOR.sh <1dphysiolog> <4doutput> <1dsliacqtime> "
    echo ""
    echo ""
    exit
}

[ "$2" = "" ] && Usage

pfile=${1}
input=`${FSLDIR}/bin/remove_ext ${2}`
tfile=${3} # 1dsliacqtime

# remove later
#physiofile="/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL/Physio/PhysioLog.txt"
#input="/mnt/hcp01/WU_MINN_HCP/100206/rfMRI_REST1_RL/rfMRI_REST1_RL_orig.nii.gz"
#tfile="/mnt/hcp01/SLOMOCO_HCP/SliceAcqTime_3T_TR720ms.txt"

# define output directory
odir=`dirname $pfile`


# read tfile and calculate SMS factor  
SMSfactor=0
while IFS= read -r line; do
  # Process each line here
  #echo "Read line: $line"
  if [ $line == "0" ] || [ $line == "0.0" ] ; then
    let "SMSfactor+=1"
  fi
done < "$tfile"
echo "inplane acceleration is $SMSfactor based on slice acquisition timing file."

# read EPI info
zdim=`fslval $input dim3`
tdim=`fslval $input dim4`
tr=`fslval $input pixdim4`

# sanity check

if [ $SMSfactor == 0 ] ; then
    echo "ERROR: slice acquisition timing does not have zero"
    exit
elif [ $SMSfactor == $zdim ] ; then
    echo "ERROR: all slice acquisition timing was time-shifted to zero"
    exit
elif [ $SMSfactor != "8" ] ; then
    echo "Warning: SMS factor in 3T HCP is expected to be 8."
fi

echo "Generate Slicewise physio regressor 1D file"
# will be replaced with MCR 
matlab -nodesktop -nosplash -r "addpath $PESTICADIR; readHCPPhysio('${pfile}','${tfile}','${odir}',${tr},${tdim},${zdim},${SMSfactor}); exit;" 

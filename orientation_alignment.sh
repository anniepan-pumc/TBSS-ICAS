#!/bin/bash

# ---------------
# Instructions
# ---------------
# 1. Align orientation and match to MNI152 space with FSL and Freesurfer
# 2. Pre-require:
#   1. WMH series（nii.gz）
#   2. WMH mask series（nii.gz）
#   3. Fundation brain MRI in MNI space: T2_FLAIR_brain_to_MNI.nii.gz
#   4. Fundation brain MRI to MNI space transform matrix: T2_FLAIR_orig_to_MNI_warp.nii.gz
# 3. Results:
#   1. WMH series in MNI space
#   2. WMH mask series in MNI space
#   3. WMH probability map in MNI space

# ---------------
# 参数设置
# ---------------
INITDIR="" # 初始工作文件夹
BASE_DIR="${INITDIR}"data # 数据文件夹
WMH_MASK_NAME="WMH_FLAIR_orig_ud_mask.nii.gz" # 工作mask序列名称
WMH_NAME="WMH_FLAIR_orig_ud.nii.gz" #工作序列名称
WM_MASK_NAME="T2_FLAIR_orig_ud_bianca_mask.nii.gz"
WMH_CUT_MASK_NAME="CUTTED_WMH_FLAIR_orig_ud_mask.nii.gz"
WMH_CUT_NAME="CUTTED_WMH_FLAIR_orig_ud.nii.gz"
PROBMAP_WMH_NAME="PROBMAP_WMH_FLAIR_orig_ud.nii.gz"
WMH_MERGED_PATH="$INITDIR/result" # 合并后的序列输出路径
LOG_FILE="$INITDIR/ICAS_analysis.log" # 工作输出记录
RESULT_DIR="$INITDIR/ICAS_res/" # 结果输出目录

# ---------------
# 初始化配置
# ---------------
set_SYSPATH(){
    export FREESURFER_HOME="/PATH/TO/FREESURFER"
    export SUBJECTS_DIR=$1
    export FSLDIR="/PATH/TO/FSL"
    export FS_LICENSE="FREESURFER/LICENSE.txt"
    source $FREESURFER_HOME/SetUpFreeSurfer.sh
    source $FSLDIR/etc/fslconf/fsl.sh
}

orientation_align(){
    echo "---------------------Align WMH mask...---------------------"
    for subpath in ${SUBJECTS_DIR}/*/ ; do
        if [ ! -d "$subpath" ]; then
            continue
        fi
        subfolder_name=$(basename "$subpath")
        # Skip hidden directories
        if [[ "$subfolder_name" == .* ]]; then
            continue
        fi
        # Skip directories that don't contain the substring "sub-"
        if [[ ! "$subfolder_name" == *"sub-"* ]]; then
            continue
        fi
        echo "Aligning $subfolder_name"

        # generate WMH_mask remove area outside white matter
        fslmaths ${subpath}/${WMH_MASK_NAME} -mul ${subpath}/${WM_MASK_NAME} -thr 0.5 -bin ${subpath}/${WMH_CUT_MASK_NAME}
        # generate WMH image remove area outside white matter
        fslmaths ${subpath}/${WMH_NAME} -mul ${subpath}/${WM_MASK_NAME} ${subpath}/${WMH_CUT_NAME}
        # generate WMH probability map by mask WMH mask on WMH image
        fslmaths ${subpath}/${WMH_CUT_NAME} -mas ${subpath}/${WMH_CUT_MASK_NAME} ${subpath}/${PROBMAP_WMH_NAME}

        # mapping to MNI152
        applywarp -i ${subpath}/${WMH_CUT_MASK_NAME}\
                -r ${subpath}/T2_FLAIR_brain_to_MNI.nii.gz \
                -w ${subpath}/T2_FLAIR_orig_to_MNI_warp.nii.gz \
                -o ${subpath}aligned_${WMH_MASK_NAME}

        applywarp -i ${subpath}/${WMH_CUT_NAME}\
                -r ${subpath}/T2_FLAIR_brain_to_MNI.nii.gz \
                -w ${subpath}/T2_FLAIR_orig_to_MNI_warp.nii.gz \
                -o ${subpath}aligned_${WMH_NAME}
        
        applywarp -i ${subpath}/${PROBMAP_WMH_NAME}\
                -r ${subpath}/T2_FLAIR_brain_to_MNI.nii.gz \
                -w ${subpath}/T2_FLAIR_orig_to_MNI_warp.nii.gz \
                -o ${subpath}aligned_${PROBMAP_WMH_NAME}

    done
}


main() {
    set_SYSPATH "$BASE_DIR" #设定环境变量
    orientation_align 
}

main
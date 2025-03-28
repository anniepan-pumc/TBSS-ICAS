#!/bin/bash

# ---------------
# 参数设置
# ---------------
INITDIR="" # Working Directory
SOURCE_DIR="$INITDIR/data" # Data Path
RESULT_DIR="$INITDIR/RESULT" # Output Path
WMH_MASK_NAME="aligned_WMH_FLAIR_orig_ud_mask.nii.gz" # Mask file name
WMH_NAME="aligned_WMH_FLAIR_orig_ud.nii.gz" # Series Name
WMH_PROBMAP_NAME='aligned_PROBMAP_WMH_FLAIR_orig_ud.nii.gz'
WMH_MERGED_PATH="$INITDIR/WMH_MERGED"
ALL_MASK_NAME="all_wmh_masks_merged.nii.gz"
ICAS_DATA="$INITDIR/DM.csv" # DM data path
LOG_FILE="$INITDIR/ICAS_analysis.log" # Working log
GROUP1_ID="1"        # ICAS Positive
GROUP2_ID="0"        # ICAS Negative
FWHM="10"            
CLUSTER_THRESH=0.0001 # Cluster Threshold = 0.01/0.001/0.0001

VALUE_THRESH=0.95 # p value threshold
NUM_PERM="5000"   # Number of permutations

RAND_MODE="all_wmh_probmap" # choose "all_wmh" or "all_wmh_probmap"

# --------------------
# 模型定义
# --------------------
MODELS_KEYS=("model1" "model2" "model3")
MODELS_VALUES=("" "age_base sex " "age_base sex BMI hyperlip HTN_base DM smoking ")
mkdir -p $RESULT_DIR $RESULT_DIR/TBSS_results_${MODELS_KEYS[0]} $RESULT_DIR/TBSS_results_${MODELS_KEYS[1]} $RESULT_DIR/TBSS_results_${MODELS_KEYS[2]}
TEST_MODELS_KEYS=("model3")

# ---------------
# 初始化配置
# ---------------
set_SYSPATH(){
    local subject_dir=$1
    export FREESURFER_HOME="Path/TO/FREESURFER"
    export SUBJECTS_DIR=${subject_dir}
    export FSLDIR=""
    export FS_LICENSE=""
    source $FREESURFER_HOME/SetUpFreeSurfer.sh
    source $FSLDIR/etc/fslconf/fsl.sh
}

# ---------------
# 步骤1：准备contrast文件
generate_contrasts(){
    echo "---------------------generate_contrasts----------------------"
    local model=$1
    local model_index=0

     # Find the index of the model
    for i in "${!MODELS_KEYS[@]}"; do
        if [ "${MODELS_KEYS[$i]}" = "$model" ]; then
            model_index=$i
            break 
        fi
    done
    
    local covariates="${MODELS_VALUES[$model_index]}"

    for glmm in vspos vsneg; do

        # Get number of covariates for the current model
        local model_vars=(${MODELS_VALUES[$model_index]})
        local num_vars=${#model_vars[@]}
        
        # Create string of zeros based on number of covariates
        local zeros=""
        for ((i=1; i<=$num_vars; i++)); do
            zeros+=" 0"
        done

        if [ "$glmm" = "vspos" ]; then
            echo "1 -1${zeros}" >> con_${model}_${glmm}.txt # A-B
        elif [ "$glmm" = "vsneg" ]; then
            echo "-1 1${zeros}" >> con_${model}_${glmm}.txt # B-A
        fi

        Text2Vest con_${model}_${glmm}.txt ICAS_${model}_${glmm}.con
    done
}

check_con_files() {
    local model=$1
    local pattern=".con"
    
    # Check if any matching files exist
    con_files=($(ls *$pattern 2>/dev/null))
    
    if [ ${#con_files[@]} -eq 0 ]; then
        #echo "No matrix files found for $model"
        return 1
    fi
    echo "Found ${#con_files[@]} matrix files for $model:"
    for file in "${con_files[@]}"; do
        echo "  - $file"
    done
    return 0
}

generate_matrix() {
    echo "---------------------generate_matrix----------------------"
    local model=$1
    local model_index=0
    local icas_data=$2
    # echo "/NumWaves" "4" > mat_${model}.txt
    # echo "/NumPoints" "1202" > mat_${model}.txt
    #echo "/Matrix" > mat_${model}.txt
     for i in "${!MODELS_KEYS[@]}"; do
        if [ "${MODELS_KEYS[$i]}" = "$model" ]; then
            model_index=$i
            break 
        fi
    done
    
    local covariates="${MODELS_VALUES[$model_index]}"

    # Use standard IFS and handle malformed lines
    tail -n +2 "$icas_data" | while IFS=',' read -r IDcase group age_base sex BMI hyperlip HTN_base DM smoking || [ -n "$IDcase" ]; do
        # Skip empty lines
        if [ -z "$group" ]; then
            echo "Skipping empty/invalid line: $IDcase" >&2
            continue
        fi

        # Process valid lines with awk
        echo "$group $age_base $sex $BMI $hyperlip $HTN_base $DM $smoking" | \
        awk -v cov="$covariates" '
            BEGIN { split(cov, c); n = length(c) }
            {
                printf "%s", $1  # Group
                printf "%s", ($1 == "1") ? " 0" : " 1"  # Contrast group
                for (i = 1; i <= n; i++) {
                    printf " %s", $(i + 1)
                }
                printf "\n"  # Ensure line breaks
            }
        ' >> "mat_${model}.txt"
    done

    tr '\r' '\n' < mat_${model}.txt > tmp.txt && mv tmp.txt mat_${model}.txt

    Text2Vest mat_${model}.txt ICAS_${model}.mat 

}


integrate_wmh() {
    echo "---------------------integrate_wmh_masks----------------------"

    if [ ! -f all_wmh.nii.gz ]; then
        echo "---------------------Generating 4D images...---------------------"

        fslmerge -t all_wmh.nii.gz $SUBJECTS_DIR/*/$WMH_NAME
        fslmerge -t all_wmh_probmap.nii.gz $SUBJECTS_DIR/*/$WMH_PROBMAP_NAME
    fi
}


randomize(){
    local model=$1              # First argument = model name
    local rand_input=$2
    local con_files=("${@:3}")  # Remaining arguments = contrast files

    echo "---------------------Randomize----------------------"
    for contrast in "${con_files[@]}"; do
        contrast_name=$(basename "$contrast" .con)
        echo "Processing contrast: $contrast_name"
        
        # Unique output prefix for randomise
        randomise -i ${rand_input}.nii.gz \
                -o tbss_${contrast_name} \
                -m ${WMH_MERGED_PATH}/${ALL_MASK_NAME} \
                -d ICAS_${model}.mat \
                -t "$contrast" \
                -n $NUM_PERM \
                --T2
        
        # Update paths to match randomise output prefix
        fslmaths "tbss_${contrast_name}_tfce_corrp_tstat1.nii.gz" -thr $VALUE_THRESH "${contrast_name}_thr95.nii.gz"
        
        cluster --in="${contrast_name}_thr95.nii.gz" \
                --thresh="${CLUSTER_THRESH}" \
                --oindex="${contrast_name}_cluster_index" \
                --olmax="${contrast_name}_lmax.txt" \
                --osize="${contrast_name}_cluster_size"
        
        autoaq -i "tbss_${contrast_name}_tfce_corrp_tstat1" \
            -t $VALUE_THRESH \
            -o "${contrast_name}_report.txt" \
            -a "JHU ICBM-DTI-81 White-Matter Labels"
    done
}

# ---------------
# 主流程控制
# ---------------
main() {
    echo "ICAS Analysis Log - $(date)" > "$LOG_FILE"
    set_SYSPATH "$SOURCE_DIR"
    {
        for model in "${MODELS_KEYS[@]}"; do
            cd $RESULT_DIR/TBSS_results_${model}
            echo "Working with model: $model"
            generate_contrasts "$model"
            generate_matrix "$model" "$ICAS_DATA"    # Removed the parentheses
            check_con_files "$model" 
            integrate_wmh
            randomize  "$model" "$RAND_MODE" "${con_files[@]}"
            echo "{$model} Analysis Done!"
            cd $INITDIR
        done
    } 2>&1 | tee -a $LOG_FILE
}

# 执行主流程
main

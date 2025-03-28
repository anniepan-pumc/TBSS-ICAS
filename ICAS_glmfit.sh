#!/bin/bash

# ---------------
# Parameter Setting
# ---------------
INITDIR="" # Working directory
DATA_DIR=${INITDIR}/data # Data input
ICAS_DATA="$INITDIR/data/dm.csv" # Data input
LOG_FILE="$INITDIR/ICAS_analysis.log" # Working log
RESULT_DIR="$INITDIR/result/" # Result Output
RLT_PATH="$INITDIR/glmfit_res" #summarized results
GROUP1_ID="1"        # ICAS Positive
GROUP2_ID="0"        # ICAS Negative
FWHM="10"          
CLUSTER_THRESH="2.0" 
NUM_PERM="5000"      

# ---------------
# 初始化配置
# ---------------
export FREESURFER_HOME="PATH/TO/FREESURFER"
source $FREESURFER_HOME/SetUpFreeSurfer.sh
export SUBJECTS_DIR=$DATA_DIR
export FSLDIR="PATH/TO/FSL"
export FS_LICENSE="FREESURFER/license.txt"
source $FSLDIR/etc/fslconf/fsl.sh

dos2unix $ICAS_DATA  # CRLF 
sed -i 's/,\s*$//' $ICAS_DATA

# --------------------
# Model Defination
# --------------------
MODELS_KEYS=("model1" "model2" "model3")
MODELS_VALUES=("" "age_base sex" "age_base sex BMI hyperlip HTN_base DM smoking")
mkdir -p $RESULT_DIR/wmh_results_${MODELS_KEYS[0]} $RESULT_DIR/wmh_results_${MODELS_KEYS[1]} $RESULT_DIR/wmh_results_${MODELS_KEYS[2]}
TEST_MODELS_KEYS=("model3")

if [ -d "$RLT_PATH"]; then 
    echo "Already Exist"
else
    mkdir -p "${RLT_PATH}/summary" "${RLT_PATH}/mgh"
fi
# ---------------
# 步骤0：创建对比矩阵
# ---------------
generate_contrasts() {
    # column number = 组数*（协变量数+1）= 2
    # model 1 = 2*1 = 2
    
    echo "1 -1" > wmh_results_model1/ICAS_model1.mtx
    
    # model 2 number of columns = 2 * (2+1) = 6
    echo "1 -1 0 0 0 0" > wmh_results_model2/ICAS_model2.mtx
    
    # model 3 number of columns = 2 * (7+1) = 16
    echo "1 -1 0 0 0 0 0 0 0 0 0 0 0 0 0 0" > wmh_results_model3/ICAS_model3.mtx    

}

# ---------------
# Step 1: Preparing FSGD docs
# ---------------
generate_fsgds() {
    local model=$1
    local model_index=0
    local icas_data=$2
    
    # Find the index of the model
    for i in "${!MODELS_KEYS[@]}"; do
        if [ "${MODELS_KEYS[$i]}" = "$model" ]; then
            model_index=$i
            break 
        fi
    done
    
    local covariates="${MODELS_VALUES[$model_index]}"

    # Debug prints
    echo "Model: $model"
    echo "Model index: $model_index"
    echo "Covariates: $covariates"

    # Each subject line follows the order defined above:
    # Subject ID, ICAS symptom, age, sex, BMI, DM status
    # Rest of the function remains the same
    echo "GroupDescriptorFile 1" > FSGD_${model}.fsgd
    echo "Title ${model}_analysis" >> FSGD_${model}.fsgd
    echo "Class 1" >> FSGD_${model}.fsgd
    echo "Class 0" >> FSGD_${model}.fsgd
    if [ -n "$covariates" ]; then
        echo "Variables $covariates" >> FSGD_${model}.fsgd
    fi


    # Let's create a simpler approach
    tail -n +2 $icas_data | while IFS=',' read -r IDcase group age_base sex BMI hyperlip HTN_base DM smoking || [[ -n "$IDcase" ]]; do
        # Start with ID and group
        line="Input sub-0$IDcase $group"
        
        # Add each covariate if it's in the list
        for cov in $covariates; do
            case $cov in
                "age_base") line="$line $age_base" ;;
                "sex") line="$line $sex" ;;
                "BMI") line="$line $BMI" ;;
                "hyperlip") line="$line $hyperlip" ;;
                "HTN_base") line="$line $HTN_base" ;;
                "DM") line="$line $DM" ;;
                "smoking") line="$line $smoking" ;;
                "group") ;; # Group already included
            esac
        done
        
        # Output the line
        echo "$line" >> FSGD_${model}.fsgd
        
    done

    # Fix any Windows-style line endings
    tr '\r' '\n' < FSGD_${model}.fsgd > tmp.fsgd && mv tmp.fsgd FSGD_${model}.fsgd
    
    # Debug - show the resulting file
    echo "First few lines of generated FSGD file:"
    head -n 10 FSGD_${model}.fsgd
}

# ---------------
# 步骤2：获取对比矩阵
# ---------------

check_mtx_files() {
    local model=$1
    local pattern="_model${model#model}.mtx"
    
    # Check if any matching files exist
    mtx_files=($(ls *$pattern 2>/dev/null))
    
    if [ ${#mtx_files[@]} -eq 0 ]; then
        #echo "No matrix files found for $model"
        return 1
    fi
    echo "Found ${#mtx_files[@]} matrix files for $model:"
    # for file in "${mtx_files[@]}"; do
    #     echo "  - $file"
    # done
    return 0
}

# ---------------
# 步骤3：表面数据预处理
# ---------------
surface_preprocessing() {
  echo "-------surface preprocessing-------"
  local model=$1    # First parameter: data
  local FWHM=10         # Second parameter: smooth params
  local output_path=$2
  local subjects=($(tail -n +2 "$ICAS_DATA" | cut -d',' -f1))


  for hemi in lh rh; do
      for measure in volume thickness; do 
        echo "-------mris preproc-------"
        local cmd="mris_preproc --fsgd FSGD_${model}.fsgd \
                    --target fsaverage \
                    --hemi $hemi \
                    --out ${output_path}/${hemi}.${measure}.${model}.00.mgh"
        
        for subject in "${subjects[@]}"; do
            cmd+=" --isp $SUBJECTS_DIR/sub-0$subject/surf/${hemi}.${measure}"
        done

        echo "执行preproc堆叠: $hemi"
        eval $cmd
      
        echo "-------mri surf2surf-------"
        mri_surf2surf --hemi $hemi \
                      --s fsaverage \
                      --sval "${output_path}/${hemi}.${measure}.${model}.00.mgh" \
                      --fwhm $FWHM \
                      --cortex \
                      --tval "${output_path}/${hemi}.${measure}.${FWHM}.mgh"
      done
  done
}

# ---------------
# 步骤4：GLM模型拟合
# ---------------

run_glm_analysis() {
    echo "---------glm_analysis---------"
    local model=$1
    local output_path=$2
    local mtx_files=("${@:3}")
    
    for hemi in lh rh; do
        for measure in thickness volume; do
            # 构建基础命令
            local cmd="mri_glmfit --y ${hemi}.${measure}.${FWHM}.mgh \
                    --fsgd FSGD_${model}.fsgd \
                    --surf fsaverage $hemi \
                    --cortex \
                    --glmdir ${output_path}/${hemi}.${measure}.glm_results_${model} \
                    --eres-save"
            
            # 添加所有对比矩阵
            for mtx in "${mtx_files[@]}"; do
                cmd+=" --C $mtx"
            done
            
            # 执行命令
            echo "执行GLM分析: $hemi"
            eval $cmd
        done
    done
}

# ---------------
# 步骤5：多重比较校正
# ---------------
run_cluster_correction() {
    echo "---------------------cluster_correction----------------------"
    local model=$1
    local CLUSTER_THRESH=$2
    local output_path=$3

    for hemi in lh rh; do 
        for measure in thickness volume; do 
            mri_glmfit-sim --glmdir "${output_path}/${hemi}.${measure}.glm_results_${model}" --cache 1.3 abs --cwp  0.05 --2spaces  
        done 
    done 
}

result_summary() {
    local model=$1
    for hemi in lh rh ; do 
        for meas in thickness volume ; do 
            # 修复路径变量为 RESULT_DIR
            source_dir="${RESULT_DIR}/wmh_results_${model}/${hemi}.${meas}.glm_results_${model}/ICAS_${model}"
            dest_summary="${RLT_PATH}/summary/${hemi}.${meas}.${model}.cache.th13.abs.sig.cluster.summary"
            dest_mgh="${RLT_PATH}/mgh/${hemi}.${meas}.${model}.cache.th13.abs.sig.cluster.mgh"
            
            # 复制文件并验证路径
            if [ -f "$source_dir/cache.th13.abs.sig.cluster.summary" ]; then
                cp "$source_dir/cache.th13.abs.sig.cluster.summary" "$dest_summary"
            else
                echo "警告: 文件 $source_dir/cache.th13.abs.sig.cluster.summary 不存在"
            fi
            
            if [ -f "$source_dir/cache.th13.abs.sig.cluster.mgh" ]; then
                cp "$source_dir/cache.th13.abs.sig.cluster.mgh" "$dest_mgh"
            else
                echo "警告: 文件 $source_dir/cache.th13.abs.sig.cluster.mgh 不存在"
            fi
        done 
    done 
}



# ---------------
# 主流程控制
# ---------------
main() {
    echo "ICAS Analysis Log - $(date)" > "$LOG_FILE"
    {
    generate_contrasts
    for model in "${MODELS_KEYS[@]}"; do
        echo "==========================================================================================="
        echo "==========================================================================================="
        echo "正在处理模型: $model"
          # Create output directory for each model
        cd wmh_results_${model}
        current_dir="${RESULT_DIR}wmh_results_${model}"
        generate_fsgds "$model" "$ICAS_DATA"
        if check_mtx_files "$model"; then
            echo "Find matrix files: ${mtx_files[@]}"
            # ... rest of your processing ...
        else
            echo "Error: Required matrix files missing for $model"
            continue
        fi
        surface_preprocessing "$model" "$current_dir"
        run_glm_analysis "$model" "$current_dir" "${mtx_files[@]}"
        run_cluster_correction "$model" 2.0 "$current_dir"
        result_summary "$model"
        echo "{$model} analysis complete!!!"
        cd $RESULT_DIR
    done
    for hemi in lh rh; do 
        for meas in thickness volume; do 
            for model in ${MODELS_KEYS[@]}; do 
                echo ${hemi}.${meas}.${model} 
                cat ${RLT_PATH}/summary/${hemi}.${meas}.${model}.cache.th13.abs.sig.cluster.summary | grep ^["^#"] 
            done 
        done 
    done
    } 2>&1 | tee -a "$LOG_FILE"
}

# 执行主流程
main

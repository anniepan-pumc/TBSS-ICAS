#!/bin/bash

# Set directories
BASE_DIR=""
OUTPUT_DIR=""
CSV_FILE=""
WMH_MASK_FILE=""
export FREESURFER_HOME="PATH/TO/FREESURFER"
export SUBJECTS_DIR=${BASE_DIR}
source $FREESURFER_HOME/SetUpFreeSurfer.sh
export FSLDIR="PATH/TO/FSL"
export FS_LICENSE="FREESURFER/LICENSE.txt"
source $FSLDIR/etc/fslconf/fsl.sh

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create temporary files for each group
> group0_subjects.txt
> group1_subjects.txt

# Extract subject IDs by group from CSV
tail -n +2 "$CSV_FILE" | while IFS=',' read -r id group rest; do
    if [ "$group" = "0" ]; then
        echo "$id" >> group0_subjects.txt
    else
        echo "$id" >> group1_subjects.txt
    fi
done

# Function to merge WMH masks for a group
merge_group_masks() {
    local group=$1
    local subjects_file=$2
    local output_file="$OUTPUT_DIR/group${group}_wmh_masks_merged.nii.gz"
    local first_file=true
    
    while read -r id; do
        mask_path="$BASE_DIR/sub-0${id}/${WMH_MASK_FILE}"
        echo "processing id: ${id}"
        if [ -f "$mask_path" ]; then
            if [ "$first_file" = true ]; then
                fslmaths $mask_path -thr 0.5 -bin $output_file
                #cp $mask_path $output_file
                first_file=false
            else
                fslmaths $mask_path -thr 0.5 -bin "${OUTPUT_DIR}"/prep.nii.gz
                fslmaths $output_file -add ${OUTPUT_DIR}/prep.nii.gz $output_file
            fi
        fi
    done < "$subjects_file"
}

# Process each group
# echo "Processing Group 0..."
merge_group_masks 0 group0_subjects.txt

# echo "Processing Group 1..."
merge_group_masks 1 group1_subjects.txt

# echo "Processing global mask..."
fslmaths "$OUTPUT_DIR/group0_wmh_merged.nii.gz" -add "$OUTPUT_DIR/group1_wmh_merged.nii.gz"  "$OUTPUT_DIR/all_wmh_merged.nii.gz"

# Clean up temporary files
rm group0_subjects.txt group1_subjects.txt

echo "Completed! Merged masks are in $OUTPUT_DIR"

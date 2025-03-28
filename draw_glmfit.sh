SUBJECTS_DIR="PATH/TO/DATA"
MGH_RLT_DIR="PATH/TO/RESULT"

export FREESURFER_HOME="PATH/TO/FREESURFER"
source $FREESURFER_HOME/SetUpFreeSurfer.sh
export SUBJECTS_DIR=$SUBJECTS_DIR
export FSLDIR="PATH/TO/FSL"
export FS_LICENSE="FREESURFER/license.txt"
source $FSLDIR/etc/fslconf/fsl.sh

for id in $MGH_RLT_DIR/*.mgh; do 
    # Extract just the filename from the path
    filename=$(basename "$id")
    
    # Check if filename contains "rh"
    if [[ "$filename" == *"rh."* ]]; then
        # Process only right hemisphere views
        freeview -f $SUBJECTS_DIR/fsaverage/surf/rh.pial:overlay=${id}:overlay_threshold=1.3,4 -colorscale -viewport 3d -ss ${id}_rh_lat
        freeview -f $SUBJECTS_DIR/fsaverage/surf/rh.pial:overlay=${id}:overlay_threshold=1.3,4 -colorscale -viewport 3d -cam Azimuth 180 -ss ${id}_rh_mid
    else
        # Process only left hemisphere views
        freeview -f $SUBJECTS_DIR/fsaverage/surf/lh.pial:overlay=${id}:overlay_threshold=1.3,4 -colorscale -viewport 3d -ss ${id}_lh_lat
        freeview -f $SUBJECTS_DIR/fsaverage/surf/lh.pial:overlay=${id}:overlay_threshold=1.3,4 -colorscale -viewport 3d -cam Azimuth 180 -ss ${id}_lh_mid
    fi
done
#!/bin/bash
set -e

# Define the CSV file path
CSV_FILE="/path/to/your/file.csv" 

# Define the maximum number of parallel jobs (5 VMs)
MAX_PARALLEL_JOBS=5
JOBS=0

# Read the CSV file and process each line (skipping the header)
{
    read  
    while IFS=',' read -r PROJECT_ID ZONE VM_NAME DISK_NAME NEW_DISK_NAME IMAGE_NAME IMAGE_NAME_BYOL DESTINATION_URI LOG_LOCATION REGION DISK_TYPE; do  
        # Trim whitespace and carriage return characters
        PROJECT_ID=$(echo "$PROJECT_ID" | tr -d '\r')
        ZONE=$(echo "$ZONE" | tr -d '\r')
        VM_NAME=$(echo "$VM_NAME" | tr -d '\r')
        DISK_NAME=$(echo "$DISK_NAME" | tr -d '\r')
        NEW_DISK_NAME=$(echo "$NEW_DISK_NAME" | tr -d '\r')
        IMAGE_NAME=$(echo "$IMAGE_NAME" | tr -d '\r')
        IMAGE_NAME_BYOL=$(echo "$IMAGE_NAME_BYOL" | tr -d '\r')
        DESTINATION_URI=$(echo "$DESTINATION_URI" | tr -d '\r')
        LOG_LOCATION=$(echo "$LOG_LOCATION" | tr -d '\r')
        REGION=$(echo "$REGION" | tr -d '\r')
        DISK_TYPE=$(echo "$DISK_TYPE" | tr -d '\r')

        # Check if any required variables are missing
        if [ -z "$PROJECT_ID" ] || [ -z "$ZONE" ] || [ -z "$VM_NAME" ] || [ -z "$DISK_NAME" ] || [ -z "$NEW_DISK_NAME" ] || [ -z "$IMAGE_NAME" ] || [ -z "$IMAGE_NAME_BYOL" ] || [ -z "$DESTINATION_URI" ] || [ -z "$LOG_LOCATION" ] || [ -z "$REGION" ] || [ -z "$DISK_TYPE" ]; then  
            echo "Error: Missing required variables for VM: $VM_NAME. Skipping..."
            continue
        fi

        # Function to check if the image exists
        image_exists() {
            gcloud compute images describe "$IMAGE_NAME" --project="$PROJECT_ID" --format='get(name)' &> /dev/null
            return $?
        }

        # Function to check if the BYOL image has been imported
        byol_image_imported() {
            gcloud compute images describe "$IMAGE_NAME_BYOL" --project="$PROJECT_ID" --format='get(name)' &> /dev/null
            return $?
        }

        # Function to wait until the BYOL image import state changes
        wait_for_image_import() {
            while true; do
                state=$(gcloud alpha migration vms image-imports describe "$IMAGE_NAME_BYOL" --location="$REGION" | grep state: | awk '/state:/ {print $2}')
                
                if [ "$state" == "SUCCEEDED" ]; then
                    echo "BYOL image import state is SUCCEEDED."
                    break
                elif [ "$state" == "FAILED" ]; then
                    echo "Error: BYOL image import failed."
                    exit 1
                else
                    echo "Current state is $state. Checking again in 90 seconds..."
                    sleep 90
                fi
            done
        }

        # Function to check if the VM is running
        is_vm_running() {
            gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format='get(status)' | grep -q 'RUNNING'
        }

        # Function to check if the disk is attached
        is_disk_attached() {
            gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format='get(disks)' | grep -q "$DISK_NAME"
        }
        
        # Function to start the instance
        start_instance() {
            if is_vm_running; then
                echo "Instance $VM_NAME is already running. Skipping start operation."
                return
            fi
            echo "Starting instance $VM_NAME..."
            if ! gcloud compute instances start "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID"; then
                printf "Error: Failed to start instance %s.\n" "$VM_NAME" >&2
                return 1
            fi
        }

        # Function to stop the instance
        stop_instance() {
            if ! is_vm_running; then
                echo "Instance $VM_NAME is already stopped. Skipping stop operation."
                return
            fi
            echo "Stopping instance $VM_NAME..."
            if ! gcloud compute instances stop "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID"; then
                printf "Error: Failed to stop instance %s.\n" "$VM_NAME" >&2
                return 1
            fi
        }

        # Function to detach the boot disk
        detach_disk() {
            if ! is_disk_attached; then
                echo "Disk $DISK_NAME is already detached from $VM_NAME. Skipping detach operation."
                return
            fi
            echo "Detaching disk $DISK_NAME from $VM_NAME..."
            if ! gcloud compute instances detach-disk "$VM_NAME" --disk="$DISK_NAME" --zone="$ZONE" --project="$PROJECT_ID"; then
                printf "Error: Failed to detach disk %s from %s.\n" "$DISK_NAME" "$VM_NAME" >&2
                return 1
            fi
        }

        # Function to create an image from the disk
        create_image_from_disk() {
            if image_exists; then
                echo "Image $IMAGE_NAME already exists. Skipping image creation."
                return
            fi
            echo "Creating image $IMAGE_NAME from disk $DISK_NAME..."
            if ! gcloud compute images create "$IMAGE_NAME" --source-disk="$DISK_NAME" --source-disk-zone="$ZONE" --project="$PROJECT_ID"; then
                printf "Error: Failed to create image from disk %s.\n" "$DISK_NAME" >&2
                return 1
            fi
        }

        # Function to export image to bucket as VMDK
        export_image_to_bucket() {
            if [[ -f "$DESTINATION_URI/$DISK_NAME.vmdk" ]]; then
                echo "Image $IMAGE_NAME has already been exported to bucket. Skipping export operation."
                return
            fi
            echo "Exporting image $IMAGE_NAME to bucket..."
            if ! gcloud compute images export --destination-uri "$DESTINATION_URI/$DISK_NAME.vmdk" --image "$IMAGE_NAME" --export-format=vmdk --project="$PROJECT_ID"; then
                printf "Error: Failed to export image %s to bucket.\n" "$IMAGE_NAME" >&2
                return 1
            fi
        }

        # Function to import image as BYOL
        import_image_as_byol() {
            if byol_image_imported; then
                echo "BYOL image $IMAGE_NAME_BYOL has already been imported. Skipping import operation."
                return
            fi
            echo "Importing image $IMAGE_NAME_BYOL as BYOL..."
            if ! gcloud alpha migration vms image-imports create "$IMAGE_NAME_BYOL" --source-file="$DESTINATION_URI/$DISK_NAME.vmdk" --location="$REGION" --license-type=compute-engine-license-type-byol --target-project="projects/$PROJECT_ID/locations/global/targetProjects/$PROJECT_ID"; then
                printf "Error: Failed to import image %s.\n" "$IMAGE_NAME_BYOL" >&2
                return 1
            fi

            # Wait for the image import to complete
            wait_for_image_import
        }

        # Function to create a new disk from the image
        create_new_disk() {
            if gcloud compute disks describe "$NEW_DISK_NAME" --zone="$ZONE" --project="$PROJECT_ID" &> /dev/null; then
                echo "Disk $NEW_DISK_NAME already exists. Skipping disk creation."
                return
            fi

            echo "Creating new disk $NEW_DISK_NAME from image $IMAGE_NAME_BYOL of type $DISK_TYPE..."
            if ! gcloud compute disks create "$NEW_DISK_NAME" --image="$IMAGE_NAME_BYOL" --zone="$ZONE" --type="$DISK_TYPE" --project="$PROJECT_ID"; then
                printf "Error: Failed to create new disk from image %s.\n" "$IMAGE_NAME_BYOL" >&2
                return 1
            fi
        }

        # Function to attach the new boot disk
        attach_new_disk() {
            if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format='get(disks)' | grep -q "$NEW_DISK_NAME"; then
                echo "Instance $VM_NAME already has the new boot disk attached. Skipping disk attachment."
                return
            fi

            echo "Attaching new disk $NEW_DISK_NAME to instance $VM_NAME as boot disk..."
            if ! gcloud compute instances attach-disk "$VM_NAME" --disk="$NEW_DISK_NAME" --zone="$ZONE" --boot --project="$PROJECT_ID"; then
                printf "Error: Failed to attach new disk %s to %s.\n" "$NEW_DISK_NAME" "$VM_NAME" >&2
                return 1
            fi
        }

        # Main function to orchestrate the operations
        main() {
            gcloud config set project "$PROJECT_ID"
            stop_instance
            create_image_from_disk
            export_image_to_bucket
            import_image_as_byol
            create_new_disk
            detach_disk
            attach_new_disk
            start_instance
            printf "VM %s processed successfully.\n" "$VM_NAME"
        }

        # Call the main function in the background for parallel processing
        main &

        # Increment the job count
        JOBS=$((JOBS + 1))

        # If the number of running jobs reaches the limit, wait for them to finish
        if [ "$JOBS" -ge "$MAX_PARALLEL_JOBS" ]; then
            wait
            JOBS=0  # Reset job counter after waiting for the processes
        fi

    done
} < "$CSV_FILE"  # Feed CSV data from the file

# Wait for any remaining background jobs to complete
wait

echo "Process completed!"


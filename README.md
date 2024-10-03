# VM BYOL Image Migration Script

This bash script automates the process of stopping Google Cloud VMs, creating images from their disks, exporting those images to a specified Cloud Storage bucket, and importing them as BYOL (Bring Your Own License) images. It processes multiple VMs in parallel, providing efficient resource management.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [CSV File Format](#csv-file-format)
- [How It Works](#how-it-works)
- [Error Handling](#error-handling)
- [License](#license)

## Prerequisites

- Ensure you have the Google Cloud SDK installed and configured on your system.
- Make sure you have permissions to perform operations on the Google Cloud resources used in this script (VMs, images, disks, etc.).
- The script assumes a UNIX-like environment.

## Usage

1. Clone this repository:
   ```bash
   git clone <repository_url>
   cd <repository_name>
   ```

2. Update the CSV file path in the script:
   ```bash
   CSV_FILE="/path/to/your/byol.csv"
   ```

3. Modify the CSV file to include the necessary information for your VMs (see CSV File Format below).

4. Run the script:
   ```bash
   bash your_script_name.sh
   ```

## CSV File Format

The script expects a CSV file with the following columns:

| Column            | Description                                             |
|-------------------|---------------------------------------------------------|
| PROJECT_ID        | The project ID where the VM resides.                   |
| ZONE              | The zone where the VM is located.                      |
| VM_NAME           | The name of the VM to process.                          |
| DISK_NAME         | The name of the existing boot disk.                     |
| NEW_DISK_NAME     | The name of the new disk to be created from the BYOL image. |
| IMAGE_NAME        | The name of the image created from the boot disk.      |
| IMAGE_NAME_BYOL   | The name of the BYOL image to be imported.             |
| DESTINATION_URI   | The Cloud Storage URI where the image will be exported. |
| LOG_LOCATION       | The location for logs (currently not utilized in the script). |
| REGION            | The region for the BYOL image import.                  |
| DISK_TYPE         | The type of the new disk to be created.                |

**Example CSV:**
```csv
PROJECT_ID,ZONE,VM_NAME,DISK_NAME,NEW_DISK_NAME,IMAGE_NAME,IMAGE_NAME_BYOL,DESTINATION_URI,LOG_LOCATION,REGION,DISK_TYPE
my-project,us-central1-a,my-vm,boot-disk,new-boot-disk,my-image,my-byol-image,gs://my-bucket/image-export,gs://my-bucket/logs,us-central1,pd-standard
```

## How It Works

1. **Parallel Processing:** The script reads the CSV file, processes each VM entry, and runs the operations in parallel, limited to a specified number of concurrent jobs (default: 5).
   
2. **Image Creation and Export:** For each VM, the script stops the VM, creates an image from its boot disk, exports it to a Cloud Storage bucket, and imports it as a BYOL image.

3. **Disk Management:** The script detaches the old boot disk and attaches the newly created disk to the VM before starting it again.

4. **Error Handling:** The script includes error checking to ensure that required variables are present and that operations complete successfully.

## Error Handling

The script includes error handling mechanisms to manage various scenarios, such as:

- Missing required variables.
- Failed operations for starting/stopping VMs, creating images, and importing BYOL images.

When an error occurs, the script logs the issue and continues processing the next VM entry.

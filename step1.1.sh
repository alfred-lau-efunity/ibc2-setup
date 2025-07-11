#!/bin/bash

set -e  # Exit on any error

sudo apt-get update
sudo apt install xrdp -y
sudo apt install xfce4 xfce4-session -y
echo "xfce4-session" > ~/.xsession
sudo apt install ubuntu-desktop -y
 
sudo systemctl enable --now xrdp
 
sudo systemctl restart xrdp
sudo ufw allow 3389/tcp

echo "✅ RDP set up"

#############################################################################

DEVICE_DATA_PATH="/var/tmp/device_data.json"
OUTPUT_YAML_PATH="/home/user/fsa_programs/aws_iot_env_setup/GreengrassInstaller/config.yaml"
CLAIM_CERTS_PATH="/home/user/fsa_programs/aws_iot_env_setup/claim-certs"

sudo timedatectl set-timezone Asia/Singapore
timedatectl

if [ ! -d "$CLAIM_CERTS_PATH" ]; then
  echo "Error: claim-certs directory not found."
  exit 1
fi

if [ ! -f "$DEVICE_DATA_PATH" ]; then
  echo "Error: Device data file not found at $DEVICE_DATA_PATH" >&2
  exit 1
fi

DEVICE_ID=$(jq -r '.DeviceId' "$DEVICE_DATA_PATH")
if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" == "null" ]; then
  echo "Error: DeviceId not found in $DEVICE_DATA_PATH" >&2
  exit 1
fi

#############################################################################

# DeepFace Models Downloader
# Downloads all release files from deepface_models v1.0 release


# Configuration
RELEASE_URL="https://github.com/serengil/deepface_models/releases/tag/v1.0"
TEMP_DOWNLOAD_DIR="/home/user/deepface_weights"
FINAL_DIR="/home/ggc_user/.deepface/weights"
API_URL="https://api.github.com/repos/serengil/deepface_models/releases/tags/v1.0"

echo "DeepFace Models Downloader"
echo "=========================="

# Create the temporary download directory if it doesn't exist
echo "Creating temporary download directory: $TEMP_DOWNLOAD_DIR"
mkdir -p "$TEMP_DOWNLOAD_DIR"

# Get release information from GitHub API
echo "Fetching release information..."
RELEASE_DATA=$(curl -s "$API_URL")

if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch release information from GitHub API"
    exit 1
fi

# Check if release data is valid
if echo "$RELEASE_DATA" | grep -q "Not Found"; then
    echo "Error: Release not found. Please check the repository and tag."
    exit 1
fi

# Extract download URLs for all assets
DOWNLOAD_URLS=$(echo "$RELEASE_DATA" | grep -o '"browser_download_url": *"[^"]*"' | sed 's/"browser_download_url": *"//;s/"//')

if [ -z "$DOWNLOAD_URLS" ]; then
    echo "Error: No download URLs found in the release."
    exit 1
fi

# Count total files
TOTAL_FILES=$(echo "$DOWNLOAD_URLS" | wc -l)
echo "Found $TOTAL_FILES files to download"
echo ""

# Download each file
CURRENT=1
echo "$DOWNLOAD_URLS" | while IFS= read -r url; do
    if [ -n "$url" ]; then
        # Extract filename from URL
        FILENAME=$(basename "$url")
        FILEPATH="$TEMP_DOWNLOAD_DIR/$FILENAME"
        DESTPATH="$FINAL_DIR/$FILENAME"
        
        echo "[$CURRENT/$TOTAL_FILES] Downloading: $FILENAME"
        
        # Check if file already exists
        if [ -f "$FILEPATH" ]; then
            echo "  File already exists, skipping..."
        else
            echo " $DESTPATH not found"
            # Download with progress bar
            if curl -L -o "$FILEPATH" "$url" --progress-bar; then
                echo "  ✓ Downloaded successfully"
            else
                echo "  ✗ Failed to download $FILENAME"
                rm -f "$FILEPATH"  # Remove partial file
            fi
        fi
        
        echo ""
        CURRENT=$((CURRENT + 1))
    fi
done

echo "All files downloaded to temporary directory: $TEMP_DOWNLOAD_DIR"

# Create final directory structure with sudo
echo "Creating final directory structure..."
sudo mkdir -p "$FINAL_DIR"

# Move files to final location with sudo
echo "Moving files to final location..."
if sudo mv "$TEMP_DOWNLOAD_DIR"/* "$FINAL_DIR/"; then
    echo "✓ Files moved successfully to $FINAL_DIR"
    
    # Clean up temporary directory
    echo "Cleaning up temporary directory..."
    rmdir "$TEMP_DOWNLOAD_DIR"
    echo "✓ Temporary directory removed"
else
    echo "✗ Failed to move files to final location"
    echo "Files remain in: $TEMP_DOWNLOAD_DIR"
    exit 1
fi

echo "Download and installation completed!"
echo "Files installed to: $FINAL_DIR"

# List installed files
echo ""
echo "Installed files:"
sudo ls -la "$FINAL_DIR"

#############################################################################

# Generate YAML file

sudo cat > "$OUTPUT_YAML_PATH" <<EOF
---
services:
  aws.greengrass.Nucleus:
    version: "2.14.3" 
    configuration:
      iotDataEndpoint: "a3uufza68x6j27-ats.iot.ap-southeast-1.amazonaws.com"
      iotCredEndpoint: "c3jdtpqz1xm73h.credentials.iot.ap-southeast-1.amazonaws.com"
      greengrassDataPlaneEndpoint: "iotdata"
      greengrassDataPlanePort: 443
  aws.greengrass.FleetProvisioningByClaim:
    configuration:
      rootPath: "/greengrass/v2"
      awsRegion: "ap-southeast-1"
      mqttPort: 443
      iotDataEndpoint: "a3uufza68x6j27-ats.iot.ap-southeast-1.amazonaws.com"
      iotCredentialEndpoint: "c3jdtpqz1xm73h.credentials.iot.ap-southeast-1.amazonaws.com"
      iotRoleAlias: "GreengrassCoreTokenExchangeRoleAlias"
      provisioningTemplate: "ClaimCert_Prov_Test_Kelvin" 
      claimCertificatePath: "/greengrass/v2/claim-certs/28fdb0c42593d3e6735b7bc93e45953a4544567f714882560cc5b676723bc989-certificate.pem.crt" 
      claimCertificatePrivateKeyPath: "/greengrass/v2/claim-certs/28fdb0c42593d3e6735b7bc93e45953a4544567f714882560cc5b676723bc989-private.pem.key"
      rootCaPath: "/greengrass/v2/AmazonRootCA1.pem"
      templateParameters:
        DeviceId: "$DEVICE_ID"
EOF

echo "✅ config.yaml generated at $OUTPUT_YAML_PATH with DeviceId: $DEVICE_ID"

## Start provisioning process
sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE \
  -jar /home/user/fsa_programs/aws_iot_env_setup/GreengrassInstaller/lib/Greengrass.jar \
  --trusted-plugin /home/user/fsa_programs/aws_iot_env_setup/GreengrassInstaller/aws.greengrass.FleetProvisioningByClaim.jar \
  --init-config /home/user/fsa_programs/aws_iot_env_setup/GreengrassInstaller/config.yaml \
  --component-default-user ggc_user:ggc_group \
  --setup-system-service true

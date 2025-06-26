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
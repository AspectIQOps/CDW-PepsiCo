#!/bin/bash
set -e

SSM_PATH="/aspectiq/demo"

# Database
aws ssm put-parameter --name "${SSM_PATH}/DB_NAME" --value "appd_licensing" --type "String" --overwrite
aws ssm put-parameter --name "${SSM_PATH}/DB_USER" --value "appd_ro" --type "String" --overwrite
aws ssm put-parameter --name "${SSM_PATH}/DB_PASSWORD" --value "appd_pass" --type "SecureString" --overwrite

# ServiceNow
aws ssm put-parameter --name "${SSM_PATH}/SN_INSTANCE" --value "dev295015" --type "String" --overwrite
aws ssm put-parameter --name "${SSM_PATH}/SN_USER" --value "snow_etl" --type "String" --overwrite
aws ssm put-parameter --name "${SSM_PATH}/SN_PASS" --value "AspectIQ1!" --type "SecureString" --overwrite

# AppDynamics
aws ssm put-parameter --name "${SSM_PATH}/APPD_CONTROLLER" --value "data202509290657533.saas.appdynamics.com" --type "String" --overwrite
aws ssm put-parameter --name "${SSM_PATH}/APPD_ACCOUNT" --value "data202509290657533" --type "String" --overwrite
aws ssm put-parameter --name "${SSM_PATH}/APPD_CLIENT_ID" --value "appd_etl" --type "String" --overwrite
aws ssm put-parameter --name "${SSM_PATH}/APPD_CLIENT_SECRET" --value "20eb4005-c467-448b-9c16-64c191a34681" --type "SecureString" --overwrite

echo "✅ All parameters uploaded to ${SSM_PATH}"

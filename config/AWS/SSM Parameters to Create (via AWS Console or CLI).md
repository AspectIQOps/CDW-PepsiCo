# Database credentials
aws ssm put-parameter --name "/pepsico/appdynamics/prod/DB_NAME" \
  --value "appd_licensing" --type String

aws ssm put-parameter --name "/pepsico/appdynamics/prod/DB_USER" \
  --value "etl_analytics" --type String

aws ssm put-parameter --name "/pepsico/appdynamics/prod/DB_PASSWORD" \
  --value "your_secure_password" --type SecureString

aws ssm put-parameter --name "/pepsico/appdynamics/prod/GRAFANA_DB_PASSWORD" \
  --value "grafana_secure_password" --type SecureString

# AppDynamics (when available)
aws ssm put-parameter --name "/pepsico/appdynamics/prod/APPD_CONTROLLER" \
  --value "https://customer.saas.appdynamics.com" --type String

# ServiceNow
aws ssm put-parameter --name "/pepsico/appdynamics/prod/SN_INSTANCE" \
  --value "dev123456" --type String

aws ssm put-parameter --name "/pepsico/appdynamics/prod/SN_USER" \
  --value "your_user" --type String

aws ssm put-parameter --name "/pepsico/appdynamics/prod/SN_PASS" \
  --value "your_pass" --type SecureString
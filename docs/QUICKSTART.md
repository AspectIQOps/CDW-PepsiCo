Workflow AWS EC2 RDS

Configure AWS session
aws configure
AWS Access Key ID [None]: AKIA5YSEURX6WC5DJIX7
AWS Secret Access Key [None]: 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
Default region name [None]: us-east-2
Default output format [None]: json


Create RDS Instance
aws rds create-db-instance \
  --db-instance-identifier pepsico-analytics-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 17.6 \
  --master-username postgres \
  --master-user-password "postgrespassword" \
  --allocated-storage 10 \
  --storage-type gp2 \
  --db-name cost_analytics_db \
  --vpc-security-group-ids sg-04bcb80f17d14777d \
  --region us-east-2 \
  --publicly-accessible \
  --no-multi-az \
  --backup-retention-period 0 \
  --no-deletion-protection

Create EC2 Instance
aws ec2 run-instances \
  --image-id ami-0ea3c35c5c3284d82 \
  --instance-type t3.micro \
  --iam-instance-profile Name=aspectiq-demo-role \
  --security-group-ids sg-04bcb80f17d14777d \
  --region us-east-2 \
  --key-name aws-test-key \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=\"pepsico-analytics\"}]" \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp2,DeleteOnTermination=true}"

Get EC2 Public IP
aws ec2 describe-instances --filters "Name=tag:Name,Values=pepsico-analytics" "Name=instance-state-name,Values=running" --region us-east-2 --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

Or Public DNS
aws ec2 describe-instances --filters "Name=tag:Name,Values=pepsico-analytics" "Name=instance-state-name,Values=running" --region us-east-2 --query 'Reservations[0].Instances[0].PublicDnsName' --output text

—optional
Get RDS Instance Name
aws rds describe-db-instances \
  --db-instance-identifier pepsico-analytics-db \
  --region us-east-2 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text

Store the RDS endpoint in SSM
-this will loop until the status is available then write the db name into the parameter store

while true; do
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier pepsico-analytics-db \
    --region us-east-2 \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)
  echo "Current status: $STATUS"
  if [[ "$STATUS" == "available" ]]; then
    echo "RDS is ready."
    break
  fi
  sleep 15
done

RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier pepsico-analytics-db \
  --region us-east-2 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

aws ssm put-parameter \
  --name "/pepsico/DB_HOST" \
  --value "$RDS_ENDPOINT" \
  --type "String" \
  --overwrite \
  --region us-east-2

echo "RDS endpoint stored in SSM: $RDS_ENDPOINT"


SSH into EC2 Instance from folder where the AWS key is stored
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=pepsico-analytics" "Name=instance-state-name,Values=running" \
  --region us-east-2 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i aws-test-key.pem ubuntu@$EC2_IP

Verify connection from terminal
nc -zv $(aws ssm get-parameter --name "/pepsico/DB_HOST" --region us-east-2 --query 'Parameter.Value' --output text) 5432

Expected output:
Connection to pepsico-analytics-db.*****us-east-2.rds.amazonaws.com port 5432 [tcp/postgresql] succeeded!

CLone Repo to EC2 instance
git clone https://github.com/AspectIQOps/CDW-PepsiCo.git

Run ec2_initial_setup.sh
ALL-IN-ONE Setup Script (Recommended for fresh EC2)

./scripts/utils/ec2_initial_setup.sh

What it does:
1. Updates system packages
2. Installs Docker + Docker Compose
3. Installs AWS CLI
4. Installs PostgreSQL client
5. Installs Python dependencies
6. Clones the git repo
7. Verifies SSM parameters exist
8. Tests database connection
9. Creates .env file
10. Builds Docker image
Use when: Starting from a completely fresh EC2 instance with nothing installed.

Run init_databse.sh

chmod +x scripts/setup/init_database.sh
./scripts/setup/init_database.sh

What it does:
1. Creates users, tables, seed data
2. Single complete initialization

Run platform_manager.sh start

./scripts/utils/platform_manager.sh start
./scripts/utils/platform_manager.sh logs

What it does:
1. Starts the ETL pipeline

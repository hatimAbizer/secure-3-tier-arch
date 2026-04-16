#!/bin/bash

# Update + install essentials
dnf update -y
dnf install -y aws-cli unzip nodejs

# App directory
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

# ── Fetch secrets from SSM ─────────────────────────────
DB_HOST=$(aws ssm get-parameter \
  --name "/myapp/db/host" \
  --query "Parameter.Value" --output text --region ${region})

DB_NAME=$(aws ssm get-parameter \
  --name "/myapp/db/name" \
  --query "Parameter.Value" --output text --region ${region})

DB_USER=$(aws ssm get-parameter \
  --name "/myapp/db/username" \
  --query "Parameter.Value" --output text --region ${region})

DB_PASS=$(aws ssm get-parameter \
  --name "/myapp/db/password" \
  --with-decryption \
  --query "Parameter.Value" --output text --region ${region})

# ── Create .env file ───────────────────────────────────
cat > .env << EOF
APP_PORT=${app_port}
NODE_ENV=production
AWS_REGION=${region}
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
EOF

chmod 600 .env

# ── Download app from S3 ───────────────────────────────
aws s3 cp s3://${artifact_bucket}/app.zip app.zip
unzip app.zip
rm app.zip

# ── Install dependencies ───────────────────────────────
npm install

# ── Start app ───────────────────────────────────────────
nohup node server.js > app.log 2>&1 &
#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "Bootstrap started: $(date)"

dnf clean all
dnf update -y
dnf install -y aws-cli unzip

# Ensure SSM agent is installed and running (needed for CI/CD deployment)
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

# Terraform will inject 'region' here, but we escape the bash-specific $2
get_param() {
  aws ssm get-parameter --name "$1" --query "Parameter.Value" --output text --region "${region}" $${2:-}
}

echo "Fetching secrets from SSM..."
DB_HOST=$(get_param "/myapp/db/host")
DB_NAME=$(get_param "/myapp/db/name")
DB_USER=$(get_param "/myapp/db/username")
DB_PASS=$(get_param "/myapp/db/password" "--with-decryption")

mkdir -p /home/ec2-user/app
cat > /home/ec2-user/app/.env << EOF
APP_PORT=${app_port}
NODE_ENV=production
AWS_REGION=${region}
DB_HOST=$DB_HOST
DB_PORT=3306
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
EOF

# Create systemd service for the Node app
cat > /etc/systemd/system/app.service << 'EOF'
[Unit]
Description=Node.js Todo App
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/app
EnvironmentFile=/home/ec2-user/app/.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Download and extract initial app bundle from S3
echo "Downloading app bundle from S3..."
aws s3 cp "s3://${artifact_bucket}/app.zip" /tmp/app.zip --region "${region}"

# Extract to temp, then move contents (handles nested folders)
unzip -o /tmp/app.zip -d /tmp/app_extract
mv /tmp/app_extract/* /home/ec2-user/app/ 2>/dev/null || true
mv /tmp/app_extract/.* /home/ec2-user/app/ 2>/dev/null || true
rm -rf /tmp/app_extract /tmp/app.zip

# Install production dependencies
cd /home/ec2-user/app
npm install --production

# Fix permissions
chown -R ec2-user:ec2-user /home/ec2-user/app

# Enable and start the service
systemctl daemon-reload
systemctl enable app.service
systemctl start app.service

# Wait for app to be ready and verify health
echo "Waiting for app to become healthy..."
for i in {1..30}; do
  if curl -sf http://localhost:${app_port}/health > /dev/null 2>&1; then
    echo "App is healthy. Bootstrap complete."
    exit 0
  fi
  echo "Attempt $i/30: waiting for app..."
  sleep 2
done

echo "WARNING: App did not become healthy within 60 seconds. Check logs with: journalctl -u app.service"
exit 1
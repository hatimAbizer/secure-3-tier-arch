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

chown -R ec2-user:ec2-user /home/ec2-user/app

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

systemctl daemon-reload
systemctl enable app.service

echo "Bootstrap done: $(date). App will start on first CI/CD deploy."
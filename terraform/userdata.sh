#!/bin/bash
# ─────────────────────────────────────────────────────────────
# userdata.sh
# Runs ONCE when EC2 first boots.
# Installs runtime, pulls secrets, registers process manager.
# Does NOT deploy app code — that is the CI/CD pipeline's job.
# ─────────────────────────────────────────────────────────────

set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "Bootstrap started: $(date)"

# Install Node.js 20
dnf update -y
dnf install -y aws-cli unzip
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs
npm install -g pm2
echo "Node $(node -v) installed."

# Create app directory
mkdir -p /home/ec2-user/app/public

# Pull DB credentials from SSM Parameter Store → write .env
# The EC2 IAM role has permission to read /myapp/* parameters.
# The app reads process.env — it never calls SSM itself.
cat > /home/ec2-user/app/.env << EOF
APP_PORT=${app_port}
NODE_ENV=production
AWS_REGION=${region}
DB_HOST=$(aws ssm get-parameter --name "/myapp/db/host"     --query "Parameter.Value" --output text --region ${region})
DB_PORT=3306
DB_NAME=$(aws ssm get-parameter --name "/myapp/db/name"     --query "Parameter.Value" --output text --region ${region})
DB_USER=$(aws ssm get-parameter --name "/myapp/db/username" --query "Parameter.Value" --output text --region ${region})
DB_PASS=$(aws ssm get-parameter --name "/myapp/db/password" --with-decryption --query "Parameter.Value" --output text --region ${region})
EOF
chmod 600 /home/ec2-user/app/.env

# PM2 ecosystem config — tells PM2 how to run the app
cat > /home/ec2-user/app/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name:        'app',
    script:      'server.js',
    cwd:         '/home/ec2-user/app',
    env_file:    '/home/ec2-user/app/.env',
    autorestart: true,
  }]
};
EOF

# Register PM2 with systemd so app survives reboots
env PATH=$PATH:/usr/bin pm2 startup systemd -u ec2-user --hp /home/ec2-user

chown -R ec2-user:ec2-user /home/ec2-user/app

echo "Bootstrap done: $(date). Waiting for CI/CD to deploy the app."

module.exports = {
  apps: [{
    name: 'app',
    script: 'server.js',
    cwd: '/home/ec2-user/app',
    autorestart: true,
    env_production: {
      NODE_ENV: 'production'
    },
    // Load .env file from app directory
    env_file: '/home/ec2-user/app/.env'
  }]
};

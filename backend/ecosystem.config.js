module.exports = {
  apps: [{
    name: 'app',
    script: 'server.js',
    cwd: '/home/ec2-user/app',
    autorestart: true,
    env: {
      NODE_ENV: 'production'
    }
  }]
};

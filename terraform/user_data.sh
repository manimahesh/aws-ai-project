#!/bin/bash
set -e

# Update system
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install dependencies
apt-get install -y curl wget git nodejs npm python3 python3-pip jq awscli

# Install yt-dlp for YouTube video processing
pip3 install yt-dlp youtube-transcript-api

# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Configure Ollama to listen on all interfaces (INSECURE - for demonstration)
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

# Restart Ollama with new configuration
systemctl daemon-reload
systemctl restart ollama
systemctl enable ollama

# Wait for Ollama to start
sleep 10

# Pull Llama 3.2 model (this takes 5-10 minutes)
# Using nohup and background to not block user_data, but with better error handling
(
  echo "Starting Llama 3.2 model download at $(date)" > /var/log/ollama-pull.log
  ollama pull llama3.2 >> /var/log/ollama-pull.log 2>&1
  if [ $? -eq 0 ]; then
    echo "Model download completed successfully at $(date)" >> /var/log/ollama-pull.log
  else
    echo "Model download FAILED at $(date)" >> /var/log/ollama-pull.log
  fi
) &

# Create application directory
mkdir -p /var/www/vulnerable-ai-app

# Create placeholder files (will be replaced by GitHub Actions deployment)
cat > /var/www/vulnerable-ai-app/server.js <<'SERVERJS'
const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end('<h1>Application not yet deployed</h1><p>Run GitHub Actions workflow to deploy the application.</p>');
});

server.listen(80, '0.0.0.0', () => {
  console.log('Placeholder server running on port 80');
});
SERVERJS

cat > /var/www/vulnerable-ai-app/index.html <<'INDEXHTML'
<!DOCTYPE html>
<html>
<head><title>Not Deployed</title></head>
<body>
<h1>Application Not Yet Deployed</h1>
<p>Run GitHub Actions workflow to deploy the application.</p>
</body>
</html>
INDEXHTML

# Create systemd service
cat > /etc/systemd/system/vulnerable-ai-app.service <<'SERVICEEOF'
[Unit]
Description=Vulnerable AI Application (Security Training)
After=network.target ollama.service

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/vulnerable-ai-app
ExecStart=/usr/bin/node /var/www/vulnerable-ai-app/server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Set permissions
chmod +x /var/www/vulnerable-ai-app/server.js

# Enable and start the service
systemctl daemon-reload
systemctl enable vulnerable-ai-app
systemctl start vulnerable-ai-app

# Create a status check script
cat > /root/check-status.sh <<'STATUSEOF'
#!/bin/bash
echo "=== Vulnerable AI Application Status ==="
echo ""
echo "Ollama Status:"
systemctl status ollama --no-pager | grep Active
echo ""
echo "Ollama Models:"
ollama list
echo ""
echo "Web Application Status:"
systemctl status vulnerable-ai-app --no-pager | grep Active
echo ""
echo "Open Ports:"
netstat -tlnp | grep -E ':(80|11434)'
echo ""
echo "Recent Application Logs:"
journalctl -u vulnerable-ai-app -n 20 --no-pager
STATUSEOF

chmod +x /root/check-status.sh

# Create deployment marker
echo "Infrastructure deployed at $(date)" > /var/log/infrastructure-ready.log

echo "EC2 configuration complete! Application ready for deployment via GitHub Actions."

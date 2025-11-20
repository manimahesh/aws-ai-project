#!/bin/bash

# SSH Key Troubleshooting Script
# Run this to diagnose SSH authentication issues

set -e

echo "================================"
echo "SSH Key Troubleshooting Tool"
echo "================================"
echo ""

# Check if key exists
if [ ! -f ~/.ssh/vulnerable-ai-demo ]; then
    echo "❌ ERROR: Private key not found at ~/.ssh/vulnerable-ai-demo"
    echo ""
    echo "Generate a new key pair with:"
    echo "ssh-keygen -t rsa -b 4096 -f ~/.ssh/vulnerable-ai-demo"
    exit 1
fi

if [ ! -f ~/.ssh/vulnerable-ai-demo.pub ]; then
    echo "❌ ERROR: Public key not found at ~/.ssh/vulnerable-ai-demo.pub"
    exit 1
fi

echo "✅ SSH key files found"
echo ""

# Check key permissions
PRIVATE_PERMS=$(stat -c %a ~/.ssh/vulnerable-ai-demo 2>/dev/null || stat -f %A ~/.ssh/vulnerable-ai-demo 2>/dev/null)
if [ "$PRIVATE_PERMS" != "600" ]; then
    echo "⚠️  WARNING: Private key has permissions $PRIVATE_PERMS (should be 600)"
    echo "   Fixing permissions..."
    chmod 600 ~/.ssh/vulnerable-ai-demo
    echo "✅ Fixed"
else
    echo "✅ Private key permissions correct (600)"
fi
echo ""

# Get key fingerprint
echo "📋 Key Fingerprint:"
ssh-keygen -lf ~/.ssh/vulnerable-ai-demo.pub
echo ""

# Show public key (for Terraform)
echo "📋 Public Key (for terraform.tfvars):"
cat ~/.ssh/vulnerable-ai-demo.pub
echo ""
echo ""

# Show private key format
echo "📋 Private Key Format:"
head -1 ~/.ssh/vulnerable-ai-demo
echo "   ... (content) ..."
tail -1 ~/.ssh/vulnerable-ai-demo
echo ""

# Detect key type
if grep -q "BEGIN OPENSSH PRIVATE KEY" ~/.ssh/vulnerable-ai-demo; then
    echo "✅ Key format: OpenSSH (recommended)"
elif grep -q "BEGIN RSA PRIVATE KEY" ~/.ssh/vulnerable-ai-demo; then
    echo "✅ Key format: RSA (also valid)"
else
    echo "❌ ERROR: Unknown key format"
    exit 1
fi
echo ""

# Get EC2 IP
echo "================================"
echo "Testing EC2 Connection"
echo "================================"
echo ""

# Check if terraform directory exists
if [ ! -d "terraform" ]; then
    echo "❌ ERROR: terraform directory not found"
    echo "   Run this script from the project root"
    exit 1
fi

cd terraform

if [ ! -f "terraform.tfstate" ]; then
    echo "⚠️  WARNING: No terraform.tfstate found"
    echo "   Have you run 'terraform apply' yet?"
    exit 1
fi

# Get EC2 IP
EC2_IP=$(terraform output -raw ec2_public_ip 2>/dev/null)
if [ -z "$EC2_IP" ]; then
    echo "❌ ERROR: Could not get EC2 IP from Terraform"
    echo "   Run 'cd terraform && terraform output'"
    exit 1
fi

echo "✅ EC2 IP: $EC2_IP"
echo ""

# Get S3 bucket name
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
echo "✅ S3 Bucket: $S3_BUCKET"
echo ""

# Test SSH connection
echo "Testing SSH connection..."
if ssh -i ~/.ssh/vulnerable-ai-demo -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$EC2_IP echo "Connection successful" 2>/dev/null; then
    echo "✅ SSH connection works!"
else
    echo "❌ SSH connection FAILED"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Verify security group allows SSH from your IP"
    echo "2. Verify EC2 instance is running: aws ec2 describe-instances --instance-ids \$(terraform output -raw ec2_instance_id)"
    echo "3. Try manual SSH: ssh -v -i ~/.ssh/vulnerable-ai-demo ubuntu@$EC2_IP"
    exit 1
fi
echo ""

# Test key matches
echo "Checking if authorized_keys matches..."
AUTHORIZED_KEY=$(ssh -i ~/.ssh/vulnerable-ai-demo -o StrictHostKeyChecking=no ubuntu@$EC2_IP "cat ~/.ssh/authorized_keys" 2>/dev/null)
LOCAL_KEY=$(cat ~/.ssh/vulnerable-ai-demo.pub)

if [ "$AUTHORIZED_KEY" = "$LOCAL_KEY" ]; then
    echo "✅ Keys match perfectly"
else
    echo "⚠️  WARNING: Keys don't match exactly"
    echo "   This might still work, but check for issues"
fi
echo ""

echo "================================"
echo "GitHub Actions Setup"
echo "================================"
echo ""

echo "To set up GitHub Actions:"
echo "1. Go to: Settings → Secrets and variables → Actions"
echo "2. Create secret: SSH_PRIVATE_KEY"
echo "3. Paste the following (entire output):"
echo ""
echo "---BEGIN COPY---"
cat ~/.ssh/vulnerable-ai-demo
echo "---END COPY---"
echo ""
echo "4. Run workflow with these inputs:"
echo "   ec2_public_ip: $EC2_IP"
echo "   s3_bucket_name: $S3_BUCKET"
echo ""

echo "================================"
echo "Manual Deployment Command"
echo "================================"
echo ""
echo "To deploy manually instead:"
echo ""
echo "cd app"
echo "sed -i 's/REPLACE_WITH_S3_BUCKET/$S3_BUCKET/g' server.js"
echo "scp -i ~/.ssh/vulnerable-ai-demo server.js index.html ubuntu@$EC2_IP:/tmp/"
echo "ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@$EC2_IP \"sudo cp /tmp/server.js /tmp/index.html /var/www/vulnerable-ai-app/ && sudo systemctl restart vulnerable-ai-app\""
echo ""

echo "✅ All checks passed!"

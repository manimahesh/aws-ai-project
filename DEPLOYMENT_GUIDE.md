# Deployment Guide

This guide explains the two-step deployment process: Terraform for infrastructure and GitHub Actions for the application.

## Architecture Overview

```
┌─────────────────────────────────────────┐
│ Step 1: Terraform (Infrastructure)     │
├─────────────────────────────────────────┤
│ - VPC, Subnets, Security Groups         │
│ - EC2 instance                           │
│ - S3 bucket with sensitive data         │
│ - IAM roles and policies                │
│ - Ollama + Llama 3.2 installation       │
│ - Placeholder application               │
└─────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────┐
│ Step 2: GitHub Actions (Application)   │
├─────────────────────────────────────────┤
│ - Deploy server.js and index.html      │
│ - Update S3 bucket reference           │
│ - Restart application service          │
└─────────────────────────────────────────┘
```

## Prerequisites

- AWS account with appropriate permissions
- Terraform installed (>= 1.0)
- SSH key pair generated
- (Optional) GitHub repository for automated deployments

## Step 1: Deploy Infrastructure with Terraform

### 1.1 Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

### 1.2 Edit terraform.tfvars

```hcl
aws_region     = "us-west-2"
project_name   = "vulnerable-ai-demo"
instance_type  = "t3.xlarge"  # Minimum for Llama 3.2
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E... your-key-here"
```

### 1.3 Initialize and Deploy

```bash
terraform init
terraform plan
terraform apply
```

**Deployment time:** 15-20 minutes
- Infrastructure creation: ~3 minutes
- EC2 user_data execution: ~10-15 minutes
  - System updates
  - Ollama installation
  - Llama 3.2 model download (~5-10 minutes)

### 1.4 Get Output Values

After Terraform completes:

```bash
# Get EC2 public IP
terraform output ec2_public_ip

# Get S3 bucket name
terraform output s3_bucket_name

# Get all outputs
terraform output
```

**Save these values** - you'll need them for application deployment.

### 1.5 Verify Infrastructure

SSH to the instance and check status:

```bash
ssh -i ~/.ssh/your-key ubuntu@<EC2_PUBLIC_IP>
sudo /root/check-status.sh
```

Expected output:
- Ollama: active (running)
- Ollama models: llama3.2
- Web Application: active (running) - showing placeholder
- Ports: 80 and 11434 open

You should see a placeholder page at `http://<EC2_PUBLIC_IP>` saying "Application not yet deployed".

## Step 2: Deploy Application

You can deploy the application using **either** GitHub Actions or manually.

### Option A: GitHub Actions (Recommended)

#### A.1 Configure GitHub Secrets

In your GitHub repository, add this secret:

| Secret Name | Value |
|------------|-------|
| `SSH_PRIVATE_KEY` | Contents of your SSH private key |

#### A.2 Run Deployment Workflow

1. Go to Actions → "Deploy Application to EC2"
2. Click "Run workflow"
3. Enter the values from Terraform outputs:
   - **EC2 Public IP:** (from `terraform output ec2_public_ip`)
   - **S3 Bucket Name:** (from `terraform output s3_bucket_name`)
4. Click "Run workflow"

**Deployment time:** ~1 minute

#### A.3 Verify Deployment

Visit `http://<EC2_PUBLIC_IP>` - you should see the full vulnerable AI application.

### Option B: Manual Deployment

#### B.1 Update server.js

From your local machine:

```bash
cd app
S3_BUCKET="<your-s3-bucket-name>"
sed -i "s/REPLACE_WITH_S3_BUCKET/$S3_BUCKET/g" server.js
```

#### B.2 Copy Files to EC2

```bash
scp -i ~/.ssh/your-key server.js index.html ubuntu@<EC2_PUBLIC_IP>:/tmp/
```

#### B.3 Install on EC2

```bash
ssh -i ~/.ssh/your-key ubuntu@<EC2_PUBLIC_IP>

# Move files
sudo cp /tmp/server.js /tmp/index.html /var/www/vulnerable-ai-app/

# Restart service
sudo systemctl restart vulnerable-ai-app

# Check status
sudo systemctl status vulnerable-ai-app
```

#### B.4 Verify Deployment

Visit `http://<EC2_PUBLIC_IP>` - you should see the vulnerable AI application.

## Updating the Application

### Using GitHub Actions

Simply run the "Deploy Application to EC2" workflow again with the same parameters. This will:
- Deploy updated application files
- Restart the service
- No downtime (except brief restart)

### Manual Update

```bash
# From app/ directory
scp -i ~/.ssh/your-key server.js index.html ubuntu@<EC2_PUBLIC_IP>:/tmp/
ssh -i ~/.ssh/your-key ubuntu@<EC2_PUBLIC_IP> "sudo cp /tmp/*.{js,html} /var/www/vulnerable-ai-app/ && sudo systemctl restart vulnerable-ai-app"
```

## Troubleshooting

### Infrastructure Issues

**Problem:** Terraform apply fails
- Check AWS credentials: `aws sts get-caller-identity`
- Ensure sufficient permissions (EC2, VPC, S3, IAM)
- Check region availability for t3.xlarge

**Problem:** EC2 instance created but user_data didn't run
```bash
# SSH to instance and check logs
ssh -i ~/.ssh/your-key ubuntu@<EC2_PUBLIC_IP>
sudo cat /var/log/cloud-init-output.log
```

**Problem:** Ollama model not downloaded
```bash
# Check download progress
sudo cat /var/log/ollama-pull.log

# Manually pull if needed
ollama pull llama3.2
```

### Application Deployment Issues

**Problem:** GitHub Actions fails with "Permission denied (publickey)"
- Verify `SSH_PRIVATE_KEY` secret is correctly formatted
- Ensure it matches the public key used in terraform.tfvars
- Check the private key includes header/footer:
  ```
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
  ```

**Problem:** Application deployed but not responding
```bash
# SSH to instance
sudo journalctl -u vulnerable-ai-app -n 50

# Common issue: Node.js not installed
which node  # Should show /usr/bin/node

# Restart service
sudo systemctl restart vulnerable-ai-app
```

**Problem:** S3 bucket name not updated in server.js
- Verify the S3 bucket name in workflow inputs matches Terraform output exactly
- Check logs: `sudo journalctl -u vulnerable-ai-app -n 20`
- Look for errors about S3 bucket not found

## Testing the Deployment

### 1. Basic Application Test

Visit `http://<EC2_PUBLIC_IP>` and verify:
- Page loads with "AI Video Summarizer" header
- Input fields visible
- Exploit buttons visible

### 2. Ollama API Test

```bash
curl http://<EC2_PUBLIC_IP>:11434/api/tags
```

Should return JSON with llama3.2 model listed.

### 3. Test Video Summarization

1. Enter a YouTube URL (e.g., `https://www.youtube.com/watch?v=dQw4w9WgXcQ`)
2. Click "Summarize Video"
3. Should see AI-generated summary (may take 30-60 seconds first time)

### 4. Test Exploits

Click "Exploit: List S3 Files" button
- Should display S3 bucket contents including sensitive files

Click "Exploit: Steal IAM Credentials" button
- Should display temporary AWS credentials

## Infrastructure Cleanup

### Destroy All Resources

```bash
cd terraform
terraform destroy
```

Confirm by typing `yes`.

This will delete:
- EC2 instance
- S3 bucket and contents
- VPC and networking
- IAM roles
- Security groups

**Note:** S3 bucket deletion may fail if versioning created multiple object versions. If this happens:

```bash
# Empty bucket first
aws s3 rm s3://<bucket-name> --recursive

# Then destroy again
terraform destroy
```

## Cost Management

### Running Costs

- **t3.xlarge EC2:** ~$0.166/hour (~$120/month if running 24/7)
- **S3 storage:** <$1/month (minimal data)
- **Data transfer:** Variable

**Estimated monthly cost:** $120-150 if running continuously

### Cost Reduction Tips

1. **Stop EC2 when not in use:**
   ```bash
   aws ec2 stop-instances --instance-ids <instance-id>
   ```

2. **Use smaller instance for testing:**
   - Change `instance_type = "t3.large"` in terraform.tfvars
   - Note: Llama 3.2 needs at least 8GB RAM

3. **Set billing alerts:**
   - AWS Console → Billing → Budgets
   - Create alert at $50, $100 thresholds

4. **Destroy when done:**
   - Always run `terraform destroy` after training sessions

## Security Reminders

This infrastructure is **INTENTIONALLY VULNERABLE**:

- ✅ Use only in isolated training AWS accounts
- ✅ Never put real sensitive data in S3 bucket
- ✅ Destroy immediately after training
- ✅ Monitor AWS costs
- ❌ Do NOT use in production
- ❌ Do NOT deploy in corporate AWS accounts
- ❌ Do NOT leave running unmonitored

## Next Steps

1. Review [README.md](README.md) for vulnerability details
2. Study [ATTACK_SCENARIOS.md](ATTACK_SCENARIOS.md) for exploitation techniques
3. Practice exploits in deployed environment
4. Reference [SECURE_VERSION.md](SECURE_VERSION.md) for proper implementations
5. Document your findings
6. **Destroy infrastructure** when complete

## Quick Reference

```bash
# Deploy infrastructure
cd terraform
terraform apply

# Get outputs
terraform output

# Deploy application (GitHub Actions)
# Actions → Deploy Application to EC2 → Run workflow

# Deploy application (manual)
cd ../app
scp -i ~/.ssh/key server.js index.html ubuntu@<IP>:/tmp/
ssh -i ~/.ssh/key ubuntu@<IP> "sudo cp /tmp/*.{js,html} /var/www/vulnerable-ai-app/ && sudo systemctl restart vulnerable-ai-app"

# Check status
ssh -i ~/.ssh/key ubuntu@<IP> sudo /root/check-status.sh

# Destroy
cd terraform
terraform destroy
```

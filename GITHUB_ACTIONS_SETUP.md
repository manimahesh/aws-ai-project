# GitHub Actions Setup Guide

This guide explains how to configure GitHub Actions to deploy the application to your EC2 instance.

## Prerequisites

1. Infrastructure already deployed via Terraform
2. GitHub repository containing this code
3. SSH key pair (same one used in Terraform)

## Setup Steps

### 1. Locate Your SSH Keys

You should have generated SSH keys for Terraform deployment. Locate them:

**Linux/Mac:**
```bash
ls -la ~/.ssh/vulnerable-ai-demo*
# Should show:
# ~/.ssh/vulnerable-ai-demo (private key)
# ~/.ssh/vulnerable-ai-demo.pub (public key)
```

**Windows:**
```powershell
dir $env:USERPROFILE\.ssh\vulnerable-ai-demo*
# Should show:
# vulnerable-ai-demo (private key)
# vulnerable-ai-demo.pub (public key)
```

### 2. Verify SSH Keys Work

Test that you can SSH to your EC2 instance:

```bash
# Get EC2 IP from Terraform
cd terraform
terraform output ec2_public_ip

# Test SSH connection
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@<EC2_PUBLIC_IP>
```

If this works, your keys are valid. If not, fix this first before setting up GitHub Actions.

### 3. Prepare SSH Private Key for GitHub Secret

The private key must be in the **correct format** for GitHub Actions.

**Display your private key:**

```bash
# Linux/Mac
cat ~/.ssh/vulnerable-ai-demo

# Windows PowerShell
Get-Content $env:USERPROFILE\.ssh\vulnerable-ai-demo -Raw
```

**Expected format (OpenSSH):**
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAACFwAAAAdzc2gtcn
NhAAAAAwEAAQAAAgEA7xQvB... (many lines)
...
-----END OPENSSH PRIVATE KEY-----
```

**Alternative format (RSA - also valid):**
```
-----BEGIN RSA PRIVATE KEY-----
MIIJKQIBAAKCAgEA7xQvB... (many lines)
...
-----END RSA PRIVATE KEY-----
```

**⚠️ IMPORTANT:**
- Include the BEGIN and END lines
- Copy the **entire** key including all lines
- Preserve line breaks exactly as shown
- Do not add extra spaces or formatting

### 4. Configure GitHub Secrets

#### Step 4.1: Navigate to Secrets

1. Go to your GitHub repository
2. Click **Settings** (repository settings, not account)
3. In left sidebar, click **Secrets and variables** → **Actions**
4. Click **New repository secret**

#### Step 4.2: Add SSH_PRIVATE_KEY Secret

**Name:** `SSH_PRIVATE_KEY`

**Value:**
- Paste your **entire private key** from step 3
- Include the `-----BEGIN` and `-----END` lines
- Ensure all line breaks are preserved

**Example of what to paste:**
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAACFwAAAAdzc2gtcn
NhAAAAAwEAAQAAAgEA7xQvB5aN8K...
... (many more lines) ...
AAAADnZ1bG5lcmFibGUtYWktZGVtbw==
-----END OPENSSH PRIVATE KEY-----
```

Click **Add secret**.

### 5. Verify Secret Format

Common issues and how to verify:

#### Issue 1: Extra Spaces or Line Breaks

**Wrong:**
```
-----BEGIN OPENSSH PRIVATE KEY-----

b3BlbnNzaC1rZXktdjEAAAAA...
```
*(Extra blank line after BEGIN)*

**Correct:**
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAA...
```

#### Issue 2: Missing Headers

**Wrong:**
```
b3BlbnNzaC1rZXktdjEAAAAA...
... (key content) ...
```
*(Missing BEGIN/END lines)*

**Correct:**
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAA...
-----END OPENSSH PRIVATE KEY-----
```

#### Issue 3: Using Public Key Instead

**Wrong:** Using contents of `vulnerable-ai-demo.pub`
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC...
```

**Correct:** Using contents of `vulnerable-ai-demo` (no .pub extension)
```
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
```

### 6. Test the Deployment

#### Step 6.1: Get Terraform Outputs

```bash
cd terraform
terraform output ec2_public_ip
terraform output s3_bucket_name
```

Save these values.

#### Step 6.2: Run GitHub Actions Workflow

1. Go to your GitHub repository
2. Click **Actions** tab
3. Select **Deploy Application to EC2** workflow
4. Click **Run workflow** button
5. Fill in the inputs:
   - **ec2_public_ip:** Paste the IP from Terraform output
   - **s3_bucket_name:** Paste the bucket name from Terraform output
6. Click **Run workflow**

#### Step 6.3: Monitor the Workflow

Watch the workflow run:
- "Checkout code" - Should succeed
- "Update server.js with S3 bucket name" - Should succeed
- "Deploy application files to EC2" - This is where SSH auth happens
- "Install and restart application" - Runs after successful deployment

### 7. Troubleshooting

#### Error: "ssh: handshake failed: ssh: unable to authenticate"

**Cause:** SSH key mismatch or formatting issue

**Solutions:**

**A. Verify the keys match:**
```bash
# Get the public key fingerprint from your local key
ssh-keygen -lf ~/.ssh/vulnerable-ai-demo.pub

# Get the fingerprint from AWS
aws ec2 describe-key-pairs --key-names vulnerable-ai-demo-deployer-key --query 'KeyPairs[0].KeyFingerprint'

# These should match!
```

**B. Regenerate and re-import the secret:**
```bash
# Display private key
cat ~/.ssh/vulnerable-ai-demo

# Copy the ENTIRE output (including BEGIN/END lines)
# Delete old SSH_PRIVATE_KEY secret in GitHub
# Create new secret with fresh copy
```

**C. Verify EC2 instance has the correct authorized_keys:**
```bash
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@<EC2_IP>
cat ~/.ssh/authorized_keys
# Should contain the public key matching your private key
```

**D. Test SSH locally first:**
```bash
# This must work before GitHub Actions will work
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@<EC2_IP> echo "Success"
```

#### Error: "Permission denied (publickey)"

**Cause:** Wrong username or key not authorized

**Solutions:**

**Check username:**
- For Ubuntu AMI, username is `ubuntu`
- Workflow uses `ubuntu` - this should be correct

**Check key is authorized on EC2:**
```bash
# SSH to instance
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@<EC2_IP>

# Check authorized keys
cat ~/.ssh/authorized_keys

# Should contain your public key
```

#### Error: "Host key verification failed"

**Solution:** This is rare but can happen if you've destroyed and recreated the instance.

Update the workflow to disable strict host key checking (only for training environments):

```yaml
- name: Deploy application files to EC2
  uses: appleboy/scp-action@v1
  with:
    host: ${{ github.event.inputs.ec2_public_ip }}
    username: ubuntu
    key: ${{ secrets.SSH_PRIVATE_KEY }}
    source: "app/server.js,app/index.html"
    target: "/tmp/"
    strip_components: 1
    ssh_option: "-o StrictHostKeyChecking=no"  # Add this line
```

### 8. Alternative: Test SSH Key Format

Create a test script to verify your key format:

```bash
# Save your private key to a test file
cat ~/.ssh/vulnerable-ai-demo > /tmp/test-key

# Set correct permissions
chmod 600 /tmp/test-key

# Test SSH
ssh -i /tmp/test-key ubuntu@<EC2_IP> echo "Success"

# If this works, copy the EXACT contents to GitHub Secret
cat /tmp/test-key

# Clean up
rm /tmp/test-key
```

### 9. Key Generation Best Practices

If you need to regenerate keys:

```bash
# Generate new key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vulnerable-ai-demo -N ""

# Display public key (for terraform.tfvars)
cat ~/.ssh/vulnerable-ai-demo.pub

# Display private key (for GitHub Secret)
cat ~/.ssh/vulnerable-ai-demo

# Destroy and recreate infrastructure with new key
cd terraform
terraform destroy
# Update terraform.tfvars with new public key
terraform apply

# Update GitHub Secret with new private key
```

### 10. Security Best Practices

**DO:**
- ✅ Use separate SSH keys for each project
- ✅ Never commit private keys to git
- ✅ Use GitHub Secrets for sensitive data
- ✅ Rotate keys regularly
- ✅ Delete keys when project is complete

**DON'T:**
- ❌ Share private keys
- ❌ Use the same key across multiple projects
- ❌ Store keys in plaintext files
- ❌ Commit keys to version control
- ❌ Use production keys in training environments

## Manual Deployment Alternative

If GitHub Actions continues to have issues, deploy manually:

```bash
# Update server.js
cd app
sed -i "s/REPLACE_WITH_S3_BUCKET/<your-bucket-name>/g" server.js

# Copy to EC2
scp -i ~/.ssh/vulnerable-ai-demo server.js index.html ubuntu@<EC2_IP>:/tmp/

# SSH and install
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@<EC2_IP>
sudo cp /tmp/server.js /tmp/index.html /var/www/vulnerable-ai-app/
sudo systemctl restart vulnerable-ai-app
sudo systemctl status vulnerable-ai-app
exit

# Test
curl http://<EC2_IP>
```

## Quick Reference

```bash
# Generate SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vulnerable-ai-demo

# Display public key (for Terraform)
cat ~/.ssh/vulnerable-ai-demo.pub

# Display private key (for GitHub Secret)
cat ~/.ssh/vulnerable-ai-demo

# Test SSH connection
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@<EC2_IP>

# Get Terraform outputs
cd terraform
terraform output

# Manual deployment
cd ../app
scp -i ~/.ssh/vulnerable-ai-demo *.{js,html} ubuntu@<IP>:/tmp/
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@<IP> "sudo cp /tmp/*.{js,html} /var/www/vulnerable-ai-app/ && sudo systemctl restart vulnerable-ai-app"
```

## Next Steps

Once deployment succeeds:
1. Access application at `http://<EC2_PUBLIC_IP>`
2. Review [README.md](README.md) for vulnerability details
3. Study [ATTACK_SCENARIOS.md](ATTACK_SCENARIOS.md) for exploitation
4. Practice security testing
5. **Destroy infrastructure** when complete: `cd terraform && terraform destroy`

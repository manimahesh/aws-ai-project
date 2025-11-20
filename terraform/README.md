# Terraform Configuration

## Quick Start

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Generate SSH key in correct format
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vulnerable-ai-demo -C "vulnerable-ai-demo"

# Display public key
cat ~/.ssh/vulnerable-ai-demo.pub

# Edit terraform.tfvars with the public key
nano terraform.tfvars

# Deploy
terraform init
terraform apply
```

## SSH Key Format Requirements

AWS requires OpenSSH format for public keys. The key should look like:

```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... your-email@example.com
```

### Generating a Valid SSH Key

**On Linux/Mac:**
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vulnerable-ai-demo -C "vulnerable-ai-demo"
cat ~/.ssh/vulnerable-ai-demo.pub
```

**On Windows (PowerShell):**
```powershell
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\vulnerable-ai-demo" -C "vulnerable-ai-demo"
Get-Content "$env:USERPROFILE\.ssh\vulnerable-ai-demo.pub"
```

### Common Issues

**❌ Wrong Format - PEM format (will fail):**
```
-----BEGIN RSA PUBLIC KEY-----
MIIBCgKCAQEA...
-----END RSA PUBLIC KEY-----
```

**✅ Correct Format - OpenSSH format:**
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... comment
```

**❌ Wrong Format - Private key (will fail):**
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAA...
-----END OPENSSH PRIVATE KEY-----
```

**✅ Correct Format - Public key:**
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... comment
```

## Converting Existing Keys

If you have a PEM format public key, convert it:

```bash
# Convert PEM to OpenSSH format
ssh-keygen -i -f your-key.pem > openssh-key.pub

# Or generate a new key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vulnerable-ai-demo
```

## terraform.tfvars Example

```hcl
aws_region     = "us-west-2"
project_name   = "vulnerable-ai-demo"
instance_type  = "t3.xlarge"

# CORRECT - Single line, starts with ssh-rsa
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC7xQ... vulnerable-ai-demo"

# WRONG - Multi-line PEM format
# ssh_public_key = <<EOF
# -----BEGIN RSA PUBLIC KEY-----
# ...
# -----END RSA PUBLIC KEY-----
# EOF

# WRONG - Private key
# ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----..."
```

## Troubleshooting

### Error: InvalidKey.Format

```
Error: importing EC2 Key Pair: InvalidKey.Format: Key is not in valid OpenSSH public key format
```

**Solution:**
1. Verify you're using the **public** key (.pub file)
2. Ensure it's in OpenSSH format (starts with `ssh-rsa`, `ssh-ed25519`, etc.)
3. Copy the entire single line (no line breaks)
4. Ensure no extra quotes or formatting

**Verify your key format:**
```bash
# Should output: OpenSSH RSA public key
ssh-keygen -l -f ~/.ssh/vulnerable-ai-demo.pub
```

### Error: Key already exists

```
Error: creating EC2 Key Pair: InvalidKeyPair.Duplicate
```

**Solution:**
```bash
# Delete existing key in AWS
aws ec2 delete-key-pair --key-name vulnerable-ai-demo-deployer-key

# Or change project_name in terraform.tfvars
project_name = "vulnerable-ai-demo-2"
```

## After Deployment

Once Terraform completes:

```bash
# Get outputs
terraform output

# SSH to instance using your private key
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@$(terraform output -raw ec2_public_ip)

# Check infrastructure status
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@$(terraform output -raw ec2_public_ip) sudo /root/check-status.sh
```

## Variables Reference

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `aws_region` | AWS region for deployment | `us-east-1` | `us-west-2` |
| `project_name` | Project name (used in resource naming) | `vulnerable-ai-demo` | `my-ai-security-lab` |
| `instance_type` | EC2 instance type | `t3.xlarge` | `t3.large` (min 8GB RAM) |
| `ssh_public_key` | SSH public key in OpenSSH format | (required) | `ssh-rsa AAAAB3...` |

## Outputs Reference

| Output | Description | Example |
|--------|-------------|---------|
| `ec2_instance_id` | EC2 instance ID | `i-0123456789abcdef0` |
| `ec2_public_ip` | Public IP address | `54.123.45.67` |
| `web_application_url` | Application URL | `http://54.123.45.67` |
| `ollama_api_url` | Ollama API endpoint | `http://54.123.45.67:11434` |
| `s3_bucket_name` | S3 bucket with sensitive data | `vulnerable-ai-demo-sensitive-data-abc123` |
| `ssh_command` | SSH command to access instance | `ssh -i ~/.ssh/your-key ubuntu@...` |

## Next Steps

After infrastructure deployment:

1. **Wait for user_data to complete** (~15 minutes)
   - Ollama installation
   - Llama 3.2 model download
   - Application setup

2. **Verify infrastructure**
   ```bash
   ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@$(terraform output -raw ec2_public_ip) sudo /root/check-status.sh
   ```

3. **Deploy application**
   - Use GitHub Actions workflow
   - Or deploy manually (see [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md))

4. **Access application**
   ```bash
   # Get URL
   terraform output web_application_url

   # Open in browser
   # http://<EC2_PUBLIC_IP>
   ```

# GitHub Actions Setup Guide

This guide explains how to deploy the vulnerable AI infrastructure using GitHub Actions instead of manual Terraform commands.

## Prerequisites

1. AWS Account with appropriate permissions
2. GitHub repository containing this code
3. SSH key pair for EC2 access

## Setup Steps

### 1. Configure AWS Authentication (OIDC Recommended)

GitHub Actions uses OpenID Connect (OIDC) to authenticate with AWS without storing long-lived credentials.

#### Create IAM OIDC Provider

```bash
# In AWS Console or via CLI
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

#### Create IAM Role for GitHub Actions

```bash
# Create trust policy file
cat > github-actions-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:*"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name GitHubActionsVulnerableAIRole \
  --assume-role-policy-document file://github-actions-trust-policy.json

# Attach necessary permissions
aws iam attach-role-policy \
  --role-name GitHubActionsVulnerableAIRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

**Note:** For production, use more restrictive permissions. This demo uses AdministratorAccess for simplicity.

### 2. Generate SSH Key Pair

```bash
# Generate new SSH key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vulnerable-ai-demo -C "vulnerable-ai-demo"

# Display public key (for GitHub Secret)
cat ~/.ssh/vulnerable-ai-demo.pub

# Display private key (for GitHub Secret)
cat ~/.ssh/vulnerable-ai-demo
```

### 3. Configure GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions

Create the following secrets:

| Secret Name | Value | Description |
|------------|-------|-------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsVulnerableAIRole` | ARN of the IAM role created above |
| `SSH_PUBLIC_KEY` | Contents of `~/.ssh/vulnerable-ai-demo.pub` | Public SSH key for EC2 access |
| `SSH_PRIVATE_KEY` | Contents of `~/.ssh/vulnerable-ai-demo` | Private SSH key for GitHub Actions to configure EC2 |

#### How to Add Secrets:

1. Navigate to: `https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions`
2. Click "New repository secret"
3. Enter secret name and value
4. Click "Add secret"

### 4. Verify Workflow File

Ensure [`.github/workflows/deploy-vulnerable-ai.yml`](.github/workflows/deploy-vulnerable-ai.yml) exists in your repository.

### 5. Deploy Infrastructure

#### Via GitHub UI:

1. Go to the "Actions" tab in your GitHub repository
2. Select "Deploy Vulnerable AI Infrastructure" workflow
3. Click "Run workflow" button
4. Select:
   - **Action**: `apply` (to create infrastructure)
   - **AWS Region**: `us-east-1` (or your preferred region)
5. Click "Run workflow"

#### Via GitHub CLI:

```bash
# Install GitHub CLI if not already installed
# https://cli.github.com/

# Trigger deployment
gh workflow run deploy-vulnerable-ai.yml \
  -f action=apply \
  -f aws_region=us-east-1
```

### 6. Monitor Deployment

1. Go to Actions tab
2. Click on the running workflow
3. Watch the progress in real-time
4. Deployment takes approximately 15-20 minutes total:
   - Terraform apply: ~2-3 minutes
   - EC2 instance startup: ~1 minute
   - Software installation: ~5-8 minutes
   - Ollama model download: ~5-10 minutes

### 7. Access Deployed Application

After successful deployment, check the workflow summary for:

- **Web Application URL**: `http://EC2_PUBLIC_IP`
- **Ollama API URL**: `http://EC2_PUBLIC_IP:11434`
- **SSH Command**: `ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@EC2_PUBLIC_IP`

### 8. Destroy Infrastructure

When finished with training:

1. Go to Actions → Deploy Vulnerable AI Infrastructure
2. Click "Run workflow"
3. Select:
   - **Action**: `destroy`
   - **AWS Region**: Same region used for deployment
4. Click "Run workflow"

This will tear down all resources to avoid ongoing costs.

## Troubleshooting

### Workflow Fails at "Configure AWS credentials"

**Error:** `Error: Could not assume role with OIDC`

**Solution:**
- Verify `AWS_ROLE_ARN` secret is correct
- Ensure IAM role trust policy includes your repository
- Check OIDC provider is created in AWS account

### Workflow Fails at "Configure EC2 Instance"

**Error:** `Permission denied (publickey)`

**Solution:**
- Verify `SSH_PRIVATE_KEY` secret contains complete private key (including headers)
- Ensure private key format is correct (no extra spaces/newlines)
- Check that `SSH_PUBLIC_KEY` was used by Terraform to create the key pair

### Workflow Succeeds but Application Doesn't Respond

**Possible Causes:**
1. **Ollama model still downloading**: Wait 5-10 more minutes
2. **Application not started**: SSH to instance and check logs:
   ```bash
   ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@EC2_PUBLIC_IP
   sudo systemctl status vulnerable-ai-app
   sudo journalctl -u vulnerable-ai-app -n 50
   ```
3. **Security group issue**: Verify port 80 is open in AWS Console

### Check Application Status

SSH to the instance and run:

```bash
ssh -i ~/.ssh/vulnerable-ai-demo ubuntu@EC2_PUBLIC_IP
sudo /root/check-status.sh
```

This displays:
- Ollama service status
- Installed models
- Web application status
- Open ports
- Recent application logs

## Workflow Details

### What the Workflow Does:

1. **Terraform Init/Plan/Apply**: Creates AWS infrastructure
   - VPC, subnet, security groups
   - EC2 instance
   - S3 bucket with sensitive data
   - IAM roles and policies

2. **Wait for EC2**: Waits for instance to be running

3. **Configure EC2 via SSH**:
   - Updates system packages
   - Installs Node.js, Python, AWS CLI
   - Installs yt-dlp for YouTube processing
   - Installs Ollama
   - Configures Ollama to listen on all interfaces (INSECURE - intentional)
   - Downloads Llama 3.2 model

4. **Deploy Application via SCP**:
   - Copies `app/server.js` and `app/index.html` to EC2
   - Creates systemd service
   - Starts the vulnerable web application

5. **Output Information**: Displays access URLs and warnings

### Workflow Inputs:

- **action**: `apply` (deploy) or `destroy` (tear down)
- **aws_region**: AWS region for deployment (default: `us-east-1`)

### Environment Variables:

- `TF_VERSION`: Terraform version (currently `1.6.0`)
- `AWS_REGION`: Deployment region

## Security Considerations

### GitHub Secrets Security:

- **Never commit secrets to repository**
- **Use OIDC instead of access keys** when possible
- **Rotate SSH keys regularly**
- **Limit IAM role permissions** to minimum required

### Workflow Security:

- Uses `permissions: id-token: write` for OIDC
- Secrets are masked in logs
- SSH keys are never exposed in outputs

### AWS Security:

- This infrastructure is **INTENTIONALLY INSECURE**
- Only deploy in isolated training accounts
- Destroy immediately after training
- Monitor costs in AWS Billing Dashboard

## Advanced Usage

### Custom Terraform Variables

Modify the workflow to accept additional inputs:

```yaml
inputs:
  instance_type:
    description: 'EC2 instance type'
    required: false
    default: 't3.xlarge'
```

Then update the `Create terraform.tfvars` step to use the input.

### Multiple Environments

Create separate workflows for dev/staging/prod or use workflow inputs to specify environment.

### Notifications

Add Slack/Discord/Email notifications on deployment success/failure:

```yaml
- name: Notify on Success
  if: success()
  run: |
    curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
      -d '{"text":"Vulnerable AI infrastructure deployed successfully!"}'
```

## Cost Optimization

- **Stop EC2 when not in use**: Manually stop instance in AWS Console
- **Use Spot Instances**: Modify Terraform to use spot pricing
- **Auto-shutdown**: Add cron job to stop instance after hours
- **Set billing alerts**: Configure AWS Budgets to alert on spending

## Next Steps

1. Review [README.md](README.md) for vulnerability details
2. Study [ATTACK_SCENARIOS.md](ATTACK_SCENARIOS.md) for exploitation techniques
3. Reference [SECURE_VERSION.md](SECURE_VERSION.md) for proper implementations
4. Practice attacks in the deployed environment
5. Document findings and lessons learned
6. **Destroy infrastructure** when complete

## Support

For issues with:
- **GitHub Actions**: Check workflow logs and this guide
- **AWS Resources**: Review Terraform output and AWS Console
- **Application**: SSH to instance and check logs

## References

- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Terraform with GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
- [AWS IAM OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)

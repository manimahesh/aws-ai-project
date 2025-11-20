terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Configuration
resource "aws_vpc" "vulnerable_ai_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "vulnerable-ai-vpc"
    Environment = "security-training"
    Purpose     = "Demonstrating insecure AI practices"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vulnerable_ai_vpc.id

  tags = {
    Name = "vulnerable-ai-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vulnerable_ai_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "vulnerable-ai-public-subnet"
  }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vulnerable_ai_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "vulnerable-ai-public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group - INTENTIONALLY INSECURE for demonstration
resource "aws_security_group" "vulnerable_sg" {
  name        = "vulnerable-ai-sg"
  description = "INSECURE - Wide open for security training purposes"
  vpc_id      = aws_vpc.vulnerable_ai_vpc.id

  # SSH from anywhere - VULNERABILITY #1
  ingress {
    description = "SSH from anywhere - INSECURE"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP from anywhere - VULNERABILITY #2
  ingress {
    description = "HTTP from anywhere - No HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ollama API exposed - VULNERABILITY #3
  ingress {
    description = "Ollama API exposed publicly"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "vulnerable-ai-sg"
    Warning = "INTENTIONALLY_INSECURE"
  }
}

# S3 Bucket with "sensitive" data - VULNERABILITY #4
resource "aws_s3_bucket" "sensitive_data" {
  bucket = "${var.project_name}-sensitive-data-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "sensitive-data-bucket"
    Environment = "security-training"
    Contains    = "Simulated sensitive data"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# Bucket versioning
resource "aws_s3_bucket_versioning" "sensitive_data_versioning" {
  bucket = aws_s3_bucket.sensitive_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Upload sample sensitive files
resource "aws_s3_object" "customer_data" {
  bucket  = aws_s3_bucket.sensitive_data.id
  key     = "customer-pii/customers.json"
  content = jsonencode({
    customers = [
      {
        id            = "CUST-001"
        name          = "John Doe"
        email         = "john.doe@example.com"
        ssn           = "123-45-6789"
        credit_card   = "4532-1234-5678-9010"
        address       = "123 Main St, Anytown, USA"
      },
      {
        id            = "CUST-002"
        name          = "Jane Smith"
        email         = "jane.smith@example.com"
        ssn           = "987-65-4321"
        credit_card   = "5425-2334-3010-9090"
        address       = "456 Oak Ave, Somewhere, USA"
      }
    ]
  })
  content_type = "application/json"
}

resource "aws_s3_object" "api_keys" {
  bucket  = aws_s3_bucket.sensitive_data.id
  key     = "credentials/api-keys.txt"
  content = <<EOF
# Simulated API Keys - FOR TRAINING ONLY
STRIPE_API_KEY=sk_live_51ABC123DEF456GHI789JKL
OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz123456
AWS_ACCESS_KEY_ID=AKIA1234567890EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
DATABASE_PASSWORD=SuperSecret123!@#
EOF
}

resource "aws_s3_object" "financial_data" {
  bucket  = aws_s3_bucket.sensitive_data.id
  key     = "financial/revenue-report-2024.json"
  content = jsonencode({
    company      = "Example Corp"
    fiscal_year  = 2024
    quarterly_revenue = [
      { quarter = "Q1", revenue = 15000000, profit = 3500000 },
      { quarter = "Q2", revenue = 18000000, profit = 4200000 },
      { quarter = "Q3", revenue = 22000000, profit = 5100000 },
      { quarter = "Q4", revenue = 25000000, profit = 6000000 }
    ]
    confidential = true
  })
  content_type = "application/json"
}

# OVERLY PERMISSIVE IAM ROLE - VULNERABILITY #5
resource "aws_iam_role" "vulnerable_ec2_role" {
  name = "${var.project_name}-vulnerable-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name    = "vulnerable-ec2-role"
    Warning = "OVERLY_PERMISSIVE"
  }
}

# FULL S3 ACCESS - VULNERABILITY #6
resource "aws_iam_role_policy" "full_s3_access" {
  name = "full-s3-access"
  role = aws_iam_role.vulnerable_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Additional permissions for demonstration
resource "aws_iam_role_policy" "additional_permissions" {
  name = "additional-permissions"
  role = aws_iam_role.vulnerable_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "iam:GetRole",
          "iam:ListRoles",
          "secretsmanager:GetSecretValue",
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "vulnerable_profile" {
  name = "${var.project_name}-vulnerable-profile"
  role = aws_iam_role.vulnerable_ec2_role.name
}

# EC2 Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-deployer-key"
  public_key = var.ssh_public_key
}

# EC2 Instance with vulnerabilities
resource "aws_instance" "vulnerable_ai_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.vulnerable_sg.id]
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.vulnerable_profile.name
  key_name             = aws_key_pair.deployer.key_name

  # IMDSv1 enabled - VULNERABILITY #7 (enables SSRF to steal credentials)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"  # Allows IMDSv1
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  # User data configures EC2 instance with Ollama and dependencies
  user_data = templatefile("${path.module}/user_data.sh", {
    s3_bucket_name = aws_s3_bucket.sensitive_data.id
  })

  tags = {
    Name        = "vulnerable-ai-server"
    Environment = "security-training"
    Warning     = "INTENTIONALLY_INSECURE"
  }

  depends_on = [aws_s3_object.customer_data, aws_s3_object.api_keys, aws_s3_object.financial_data]
}

# Data source for Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Outputs
output "ec2_instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.vulnerable_ai_server.id
}

output "ec2_public_ip" {
  description = "Public IP of the vulnerable AI server"
  value       = aws_instance.vulnerable_ai_server.public_ip
}

output "web_application_url" {
  description = "URL to access the vulnerable web application"
  value       = "http://${aws_instance.vulnerable_ai_server.public_ip}"
}

output "ollama_api_url" {
  description = "Publicly exposed Ollama API URL"
  value       = "http://${aws_instance.vulnerable_ai_server.public_ip}:11434"
}

output "s3_bucket_name" {
  description = "S3 bucket containing sensitive data"
  value       = aws_s3_bucket.sensitive_data.id
}

output "ssh_command" {
  description = "SSH command to access the instance"
  value       = "ssh -i ~/.ssh/your-private-key ubuntu@${aws_instance.vulnerable_ai_server.public_ip}"
}

output "security_warnings" {
  description = "Critical security vulnerabilities in this setup"
  value = <<EOF
⚠️  SECURITY TRAINING ENVIRONMENT - INTENTIONAL VULNERABILITIES ⚠️

This infrastructure contains the following security issues:
1. IMDSv1 enabled - vulnerable to SSRF attacks for credential theft
2. Overly permissive IAM role with full S3 access
3. Security group allows SSH/HTTP from 0.0.0.0/0
4. No encryption at rest or in transit
5. Ollama API publicly exposed without authentication
6. No WAF, no rate limiting, no input validation
7. Sensitive data in S3 accessible via compromised instance
8. No logging, monitoring, or alerting configured
9. Application vulnerable to prompt injection attacks
10. No secrets management - credentials in plaintext

DO NOT USE IN PRODUCTION!
EOF
}

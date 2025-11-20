variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "vulnerable-ai-demo"
}

variable "instance_type" {
  description = "EC2 instance type (needs sufficient resources for Ollama)"
  type        = string
  default     = "t3.xlarge" # 4 vCPU, 16 GB RAM - needed for Llama 3.2
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
}

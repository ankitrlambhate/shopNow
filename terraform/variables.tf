variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "shopnow"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "cluster_version" {
  description = "EKS Kubernetes version. Keep it in STANDARD support (1.35: until 27 Mar 2027). Versions in extended support cost $0.60/hour instead of $0.10/hour, and 1.34 enters extended support on 2 Dec 2026."
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT cuts node cost substantially."
  type        = string
  default     = "SPOT"
}

variable "node_desired_size" {
  description = "3 small nodes leave room for shopNow (3 services + MongoDB), ingress and the monitoring stack"
  type        = number
  default     = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "ecr_namespace" {
  description = "Prefix for the ECR repositories (<namespace>/frontend, /backend, /admin)"
  type        = string
  default     = "shopnow"
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs (cheaper, less resilient)"
  type        = bool
  default     = true
}

variable "ansible_instance_type" {
  description = "EC2 type for the Ansible-managed bastion/tools host"
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair for SSH access to the bastion"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to the bastion and reach the EKS public endpoint (use your IP/32 or the Jenkins host IP/32)"
  type        = string
  default     = "0.0.0.0/0"
}

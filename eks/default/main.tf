locals {
  cluster_name = var.environment_name
}

module "tags" {
  source           = "../../lib/tags"
  environment_name = var.environment_name
}

module "vpc" {
  source           = "../../lib/vpc"
  environment_name = var.environment_name
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
  tags = module.tags.result
}

module "retail_app_eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "~> 20.31"
  cluster_name                             = local.cluster_name
  cluster_version                          = "1.33"
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  # EKS Auto Mode only
  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }
  vpc_id     = module.vpc.inner.vpc_id
  subnet_ids = module.vpc.inner.private_subnets
  tags = {
    Environment = var.environment_name
    Terraform   = "true"
  }
}

# --- Bastion SSH Key Generation ---
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "${var.environment_name}-bastion-key"
  public_key = tls_private_key.bastion.public_key_openssh
}

# --- Bastion Security Group ---
resource "aws_security_group" "bastion" {
  name        = "${var.environment_name}-bastion-sg"
  description = "Allow SSH access to bastion"
  vpc_id      = module.vpc.inner.vpc_id
  ingress {
    description = "SSH from anywhere (change for production!)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = module.tags.result
}

# --- Ubuntu AMI Data Source ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- Bastion User Data ---
locals {
  bastion_user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y curl unzip apt-transport-https ca-certificates gnupg lsb-release
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    # Install kubectl (latest stable)
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    # Install eksctl (latest)
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl /usr/local/bin
    # Clean up
    rm -rf /tmp/awscliv2.zip /tmp/aws /tmp/eksctl
    # Print versions for verification
    aws --version
    kubectl version --client
    eksctl version
  EOF
}

# --- Bastion EC2 Instance (Ubuntu) ---
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.inner.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.bastion.key_name
  user_data                   = local.bastion_user_data
  associate_public_ip_address = true
  tags = {
    Name = "${var.environment_name}-bastion"
  }
}

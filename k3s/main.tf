terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "ceramicraft-terraform-state"
    key            = "k3s/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

provider "aws" { region = var.region }

data "aws_availability_zones" "azs" {
  state = "available"
}

# pick AZ
locals {
  az = data.aws_availability_zones.azs.names[0]
}

# get cidr not conflict with 172.31.0.0/20 
# 172.31.0.0/20 = 172.31.0.0 - 172.31.15.255
# user 172.31.16.0/24 and 172.31.17.0/24
resource "aws_subnet" "public" {
  vpc_id                  = var.vpc_id
  cidr_block              = "172.31.16.0/24"
  availability_zone       = local.az
  map_public_ip_on_launch = true
  tags                    = { Name = "public-new" }
}

resource "aws_subnet" "private" {
  vpc_id            = var.vpc_id
  cidr_block        = "172.31.17.0/24"
  availability_zone = local.az
  tags              = { Name = "private-new" }
}

# public route table
resource "aws_route_table" "public" {
  vpc_id = var.vpc_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.igw_id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# security group
resource "aws_security_group" "k3s" {
  name_prefix = "k3s-demo-"
  description = "Security group for k3s control plane and workers"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "SSH access"
  }
  # traefik HTTP port
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Traefik HTTP"
  }
  # traefik HTTPS port
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Traefik HTTPS"
  }

  # in-cluster communication
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Intra-security group traffic"
  }
  # k3s API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "k3s API"
  }
  # ArgoCD NodePort
  ingress {
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "ArgoCD NodePort"
  }
  # k3s UI (kubernetes-dashboard) NodePort
  ingress {
    from_port   = 30443
    to_port     = 30443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Kubernetes dashboard NodePort"
  }
  # tailscale NodePort
  ingress {
    from_port       = 41641
    to_port         = 41641
    protocol        = "udp"
    security_groups = [var.default_sg]
    description     = "Tailscale UDP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound traffic"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  key_name               = var.key_name
  iam_instance_profile   = "EC2-S3-Role"

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  ebs_optimized = true
  monitoring    = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [ami]
  }

  tags = {
    Name     = "k3s-demo"
    AutoStop = "true"
  }
}

resource "aws_instance" "k3s_worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  key_name               = var.key_name
  iam_instance_profile   = "EC2-S3-Role"

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  ebs_optimized = true
  monitoring    = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "k3s-worker-${count.index}"
  }
  lifecycle {
    ignore_changes = [ami]
  }
}

# assign eip for each worker
resource "aws_eip" "worker_eip" {
  count    = var.worker_count
  domain   = "vpc"
  instance = aws_instance.k3s_worker[count.index].id
}

resource "null_resource" "wait_ssh" {
  depends_on = [aws_instance.k3s, aws_eip.k3s]

  provisioner "local-exec" {
    command = <<-EOT
      for i in {1..30}; do
        ssh -o StrictHostKeyChecking=no -i ${var.key_name}.pem -q ubuntu@${aws_eip.k3s.public_ip} exit && break
        echo "[$i/30] waiting for SSH …"
        sleep 10
      done
    EOT
  }
}

resource "null_resource" "ansible" {
  depends_on = [null_resource.wait_ssh]
  triggers = {
    server_id  = aws_instance.k3s.id
    worker_ids = join(",", aws_instance.k3s_worker[*].id)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "[server]" > ansible/hosts
      echo "${aws_eip.k3s.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${path.cwd}/${var.key_name}.pem" >> ansible/hosts
      
      echo "[agent]" >> ansible/hosts
      %{for ip in aws_eip.worker_eip[*].public_ip~}
      echo "${ip} ansible_user=ubuntu ansible_ssh_private_key_file=${path.cwd}/${var.key_name}.pem" >> ansible/hosts
      %{endfor~}
      
      cd ansible && ansible-playbook -i hosts playbook.yml
    EOT
  }
}


resource "aws_eip" "k3s" {
  domain   = "vpc"
  instance = aws_instance.k3s.id
}

resource "null_resource" "show_pwd" {
  depends_on = [aws_instance.k3s]

  provisioner "local-exec" {
    command = "echo ArgoCD admin password: $(ssh -o StrictHostKeyChecking=no -i ${var.key_name}.pem ubuntu@${aws_eip.k3s.public_ip} 'cat /tmp/argocd-pass')"
  }
}

resource "local_file" "ansible_inventory" {
  content  = <<EOT
[masters]
${aws_eip.k3s.public_ip} ansible_user=ubuntu

[workers]
%{for ip in aws_eip.worker_eip[*].public_ip~}
${ip} ansible_user=ubuntu
%{endfor~}

[all:vars]
ansible_ssh_private_key_file=${path.cwd}/${var.key_name}.pem
ansible_python_interpreter=/usr/bin/python3
EOT
  filename = "${path.module}/ansible/inventory.ini"
}

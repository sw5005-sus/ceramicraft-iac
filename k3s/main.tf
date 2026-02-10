terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
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
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  # k3s API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  # ArgoCD NodePort
  ingress {
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  # k3s UI (kubernetes-dashboard) NodePort
  ingress {
    from_port   = 30443
    to_port     = 30443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
#  user_data              = filebase64("${path.module}/userdata.sh")
  root_block_device {
    volume_size = 40          
    volume_type = "gp3"
  }
  tags = {
    Name = "k3s-demo"
  }  
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

  provisioner "local-exec" {
    command = <<-EOT
      EIP=${aws_eip.k3s.public_ip}
      echo "[k3s]" > ansible/hosts
      echo "$EIP ansible_user=ubuntu ansible_ssh_private_key_file=${path.cwd}/${var.key_name}.pem argo_eip=$EIP" >> ansible/hosts
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

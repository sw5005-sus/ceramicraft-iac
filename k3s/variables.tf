variable "region" { default = "ap-southeast-1" }
variable "vpc_id" { default = "vpc-0b04f8c87a79cbc3e" }       # existing VPC
variable "subnet_id" { default = "subnet-0be6cc94f8c0b1fb8" } # any public subnet in the VPC
variable "key_name" { default = "github-ec2" }                # pre-generated KeyPair
variable "my_ip" { default = "127.0.0.1/32" }                 # override with your public IP CIDR (x.x.x.x/32)
variable "igw_id" { default = "igw-06513106b987fb409" }       # pre-generated
variable "worker_count" { default = 2 }
variable "default_sg" { default = "sg-0437106d348788525" } # default ec2 security group

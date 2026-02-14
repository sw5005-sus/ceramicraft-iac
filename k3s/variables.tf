variable "region"        { default = "ap-southeast-1" }
variable "vpc_id"        { default = "vpc-0b04f8c87a79cbc3e" }   # existing VPC
variable "subnet_id"     { default = "subnet-0be6cc94f8c0b1fb8" }   # any public subnet in the VPC
variable "key_name"      { default = "github-ec2" }       # pre-generated KeyPair
variable "my_ip"         { default = "0.0.0.0/0" }    # only for experiment
variable "igw_id"    { default = "igw-06513106b987fb409" } # pre-generated
variable "worker_count" { default = 0 }

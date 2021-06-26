variable "project_name" {
  default = "k3s-playground"
}

variable "region" {
  default = "eu-west-2"
}

variable "aws_profile" {
  default = "default"
}

# Instances
variable "ami_amazon" {
  default = "ami-0895396292cca55c6c"
}

variable "instance_type" {
  default = "t3a.medium"  
}

variable "instance_type_agent" {
  default = "t3a.small"  
}

variable "volume_size" {
  default = "10"
}

variable "instance_name" {
  default = "k3s-playground"
}

variable "security_group_prefix" {
  default = "just-me"
}
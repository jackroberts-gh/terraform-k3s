provider "aws" {
  profile = var.aws_profile
  region = var.region
}

provider "random" {}

data "aws_availability_zones" "available" {
  filter {
    name = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "k3s-playground"
  cidr = "10.0.0.0/16"
  azs = data.aws_availability_zones.available.names
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    name = "k3s-playground"
  }
}

data "http" "myip" {
  url = "http://icanhazip.com"
}

resource "aws_security_group" "just_me" {
  vpc_id = module.vpc.vpc_id
  name_prefix = var.security_group_prefix
  description = "just me pls"
  
}

resource "aws_security_group_rule" "allow_http_ingress" {
  type = "ingress"
  from_port = "80"
  to_port = "80"
  protocol = "tcp"
  cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  security_group_id = aws_security_group.just_me.id
}

resource "aws_security_group_rule" "allow_http_unpriv_ingress" {
  type = "ingress"
  from_port = "8080"
  to_port = "8080"
  protocol = "tcp"
  cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  security_group_id = aws_security_group.just_me.id
}

resource "aws_security_group_rule" "allow_https_ingress" {
  type = "ingress"
  from_port = "443"
  to_port = "443"
  protocol = "tcp"
  cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  security_group_id = aws_security_group.just_me.id
}

resource "aws_security_group_rule" "allow_k3s_inbound" {
  type = "ingress"
  from_port = "6443"
  to_port = "6443"
  protocol = "tcp"
  cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  security_group_id = aws_security_group.just_me.id
}

resource "aws_security_group_rule" "allow_agress" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = -1
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.just_me.id
}

resource "aws_iam_role" "k3s_iam_role" {
  name_prefix = "k3s-iam-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid" : ""
    }
  ]
}
EOF 
}

resource "aws_iam_instance_profile" "k3s_instance_profile" {
  name_prefix = "k3s-instance-profile"
  role = aws_iam_role.k3s_iam_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_quick_setup" {
  role = aws_iam_role.k3s_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 
}
resource "aws_iam_role_policy_attachment" "ecr_power_user" {
  role = aws_iam_role.k3s_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser" 
}

resource "random_shuffle" "az" {
  input = module.vpc.public_subnets
  result_count = 2
}

resource "aws_instance" "k3s_playground" {
  subnet_id = random_shuffle.az.result[1]
  ami = var.ami_amazon
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.just_me.id]
  user_data = file("./user_data.sh")
  iam_instance_profile = aws_iam_instance_profile.k3s_instance_profile.key_name

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
    encrypted = true
  }

  tags = {
    name = var.project_name
  }

  volume_tags = {
    name = var.project_name
  }
}

resource "aws_instance" "k3s_agent" {
  subnet_id = random_shuffle.az.result[1]
  ami = var.ami_amazon
  instance_type = var.instance_type_agent
  vpc_security_group_ids = [aws_security_group.just_me.id]
  user_data = data.template_file.user_data_agent.rendered
  iam_instance_profile = aws_iam_instance_profile.k3s_instance_profile.key_name

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
    encrypted = true
  }

  tags = {
    name = var.project_name
  }

  volume_tags = {
    name = var.project_name
  }
}

data "template_file" "user_data_agent" {
  template = file("./user_data_agent.sh")
  vars = {
    master_ip = "${aws_instance.k3s_playground.public_ip}"
  }
}


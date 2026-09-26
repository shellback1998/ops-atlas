terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "ops_atlas" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = "subnet-0cb015d80df381034"
  vpc_security_group_ids      = ["sg-0d843f36fd1a9d067"]
  iam_instance_profile        = "devops-lab-ec2-profile"
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  tags = {
    Name      = "ops-atlas-aws"
    Project   = "ops-atlas"
    ManagedBy = "Terraform"
  }
}

output "instance_id" {
  value = aws_instance.ops_atlas.id
}

output "public_ip" {
  value = aws_instance.ops_atlas.public_ip
}

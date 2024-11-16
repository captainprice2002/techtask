provider "aws" {
  region = "eu-north-1"
}


terraform {
  backend "s3" {
    bucket         = "tfstate-luka"
    key            = "terraform/statefile.tfstate"
    region         = "eu-north-1"
    encrypt        = true
  }
}


resource "aws_key_pair" "default" {
  key_name   = "key-pair"
  public_key = file("${path.module}/my-key.pub")
}


resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}


resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-north-1a"
  tags = {
    Name = "main-subnet"
  }
}


resource "aws_security_group" "all_open" {
  name        = "allow-all"
  description = "Allow all inbound and outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow-all"
  }
}


resource "aws_instance" "nginx_server" {
  ami           = "ami-05fd9662cc12a5769"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main.id
  security_groups = [aws_security_group.all_open.name]
  key_name      = aws_key_pair.default.key_name

  tags = {
    Name = "nginx-server"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y ansible
              EOF
}

resource "aws_instance" "monitoring_server" {
  ami           = "ami-05fd9662cc12a5769"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main.id
  security_groups = [aws_security_group.all_open.name]
  key_name      = aws_key_pair.default.key_name

  tags = {
    Name = "monitoring-server"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y ansible
              EOF
}


resource "aws_eip" "nginx_ip" {
  instance = aws_instance.nginx_server.id
  public_ip = "13.48.181.112"
  tags = {
    Name = "nginx-server-ip"
  }
}

resource "aws_eip" "monitoring_ip" {
  instance = aws_instance.monitoring_server.id
  public_ip = "13.49.216.147"
  tags = {
    Name = "monitoring-server-ip"
  }
}

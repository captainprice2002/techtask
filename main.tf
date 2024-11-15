provider "aws" {
  region = "eu-north-1"
}

terraform {
  backend "s3" {
    bucket         = "tfstate-luka"
    key            = "terraform/state/terraform.tfstate"
    region         = "eu-north-1"
    encrypt        = true
  }
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_route_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "nginx_sg" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "my_key" {
  key_name   = "my-key"
  public_key = file("${path.module}/my-key.pub") 
}
 
resource "aws_instance" "nginx_instance" {
  ami                  = "ami-01f5d894355bd0f64"
  instance_type        = "t3.medium"
  subnet_id            = aws_subnet.public_subnet.id
  key_name             = aws_key_pair.my_key.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "Nginx-Grafana-Server"
  }

  user_data = <<-EOF
    #!/bin/bash

    while pgrep -x "yum" >/dev/null; do
      echo "Waiting for yum lock to release..."
      sleep 5
    done

    yum update -y
    amazon-linux-extras enable docker nginx1
    yum install -y docker nginx git

    systemctl start docker
    systemctl enable docker
    systemctl start nginx
    systemctl enable nginx

    if [ ! -d "/home/ec2-user/techtask" ]; then
      git clone https://github.com/captainprice2002/techtask.git /home/ec2-user/techtask
    else
      echo "Directory /home/ec2-user/techtask already exists, skipping clone."
    fi
  EOF
}


resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.nginx_instance.id
  allocation_id = "eipalloc-xxxxxxxx" # Replace with the actual Allocation ID for EIP 13.48.181.112
}

output "instance_ip" {
  value = aws_instance.nginx_instance.public_ip
}

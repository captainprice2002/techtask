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

resource "aws_instance" "nginx_instance" {
  ami             = "ami-01f5d894355bd0f64" 
  instance_type   = "t3.medium"
  subnet_id       = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "Nginx-Grafana-Server"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install ansible2 docker -y
    systemctl start docker
    systemctl enable docker
  EOF

  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y git",
      "git clone https://github.com/captainprice2002/techtask.git /home/ec2-user",
      "ansible-playbook /home/ec2-user/techtask/ansible/install_docker.yml",
      "ansible-playbook /home/ec2-user/techtask/ansible/deploy_monitoring.yml",
      "ansible-playbook /home/ec2-user/techtask/ansible/deploy_nginx.yml",
      "sudo rm -rf /etc/nginx/sites-enabled/*",
      "sudo cp /home/ec2-user/techtask/ansible/nginx/default.conf /etc/nginx/conf.d/",
      "sudo systemctl restart nginx"
    ]

    connection {
      type     = "ssh"
      user     = "ec2-user"
      host     = self.public_ip
      insecure = true
    }
  }
}

output "instance_ip" {
  value = aws_instance.nginx_instance.public_ip
}

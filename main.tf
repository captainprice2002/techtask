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
    # Wait for any other yum process to complete
    while pgrep -x "yum" >/dev/null; do
      echo "Waiting for yum lock to release..."
      sleep 5
    done

   
    yum update -y
    amazon-linux-extras enable ansible2
    yum install -y ansible docker nginx git

  
    if ! command -v ansible-playbook &> /dev/null; then
      echo "Ansible installation failed or not found in PATH."
      exit 1
    fi

   
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

  provisioner "remote-exec" {
    inline = [
      "echo 'Installing dependencies with ansible-playbook install_docker.yml'",
      "ansible-playbook /home/ec2-user/techtask/ansible/install_docker.yml || { echo 'Failed: install_docker.yml'; exit 5; }",
      
      "echo 'Running monitoring deployment playbook'",
      "ansible-playbook /home/ec2-user/techtask/ansible/deploy_monitoring.yml || { echo 'Failed: deploy_monitoring.yml'; exit 5; }",
      
      "echo 'Running NGINX deployment playbook'",
      "ansible-playbook /home/ec2-user/techtask/ansible/deploy_nginx.yml || { echo 'Failed: deploy_nginx.yml'; exit 5; }",
      
      "echo 'Removing old NGINX configurations'",
      "sudo rm -rf /etc/nginx/sites-enabled/* || { echo 'Failed to remove old NGINX config'; exit 5; }",
      
      "echo 'Copying new NGINX configuration'",
      "sudo cp /home/ec2-user/techtask/ansible/nginx/default.conf /etc/nginx/conf.d/ || { echo 'Failed to copy NGINX config'; exit 5; }",
      
      "echo 'Restarting NGINX service'",
      "sudo systemctl restart nginx || { echo 'Failed to restart NGINX'; exit 5; }"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = self.public_ip
      private_key = file("~/.ssh/my-key") 
    }
  }
}

output "instance_ip" {
  value = aws_instance.nginx_instance.public_ip
}

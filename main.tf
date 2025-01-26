provider "aws" {
  region = "us-east-1" # Replace with your preferred region
}

provider "tls" {
  # Provider to generate TLS certificates locally
}


# Key Pair for SSH access
resource "aws_key_pair" "deployer_key" {
  key_name   = "rearc-key"
  public_key = file("alroy.pub") 
}

# Security Group for HTTP and SSH
resource "aws_security_group" "web_sg" {
  name_prefix = "web-sg"
  vpc_id      = "vpc-0e236649d31a84209" 

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# TLS Certificate - Self-Signed
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed_cert" {
  private_key_pem = tls_private_key.private_key.private_key_pem

  subject {
    common_name  = "www.rearc-test.com"
    organization = "Rearc"
    country      = "IN"
    locality     = "Bangalore"
    province     = "Karnataka"
  }

  validity_period_hours = 8760 # Valid for 1 year
 
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

# Import the certificate into AWS ACM

resource "aws_acm_certificate" "self_signed_cert" {
  certificate_body       = tls_self_signed_cert.self_signed_cert.cert_pem
  private_key            = tls_private_key.private_key.private_key_pem
  certificate_chain      = tls_self_signed_cert.self_signed_cert.cert_pem
}

# IAM Role for EC2 instance to access ECR
resource "aws_iam_role" "ec2_role" {
  name = "EC2RoleForECR"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "EC2ProfileForECR"
  role = aws_iam_role.ec2_role.name
}



# EC2 Instance
resource "aws_instance" "app_instance" {
  ami           = "ami-0ac4dfaf1c5c0cce9" # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  count         = 2

  key_name = aws_key_pair.deployer_key.key_name

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  subnet_id         = element(["subnet-083e08fcc3fb8489a", "subnet-020c51a8d5fdbf428"], count.index)
  security_groups = [aws_security_group.web_sg.id]
  associate_public_ip_address = true 

  user_data = <<-EOF
              #!/bin/bash
              set -e
              echo "Cloud-init is working!" > /tmp/testfile
              sudo yum update -y  >> /var/log/user_data.log
              sudo yum install -y docker  >> /var/log/user_data.log
              sudo systemctl start docker  >> /var/log/user_data.log
              sudo systemctl enable docker  >> /var/log/user_data.log
              usermod -a -G docker ec2-user  >> /var/log/user_data.log
              sudo usermod -aG docker $(whoami)  >> /var/log/user_data.log
              echo "export LOAD_BALANCER_NAME='rearc-test-lb'" >> /etc/profile

              # Pull and run Docker container
              aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 221500065327.dkr.ecr.us-east-1.amazonaws.com  >> /var/log/user_data.log
              sudo docker pull 221500065327.dkr.ecr.us-east-1.amazonaws.com/my-docker-repo:rearc_image  >> /var/log/user_data.log
              sudo docker run -d -p 5000:5000 -e SECRET_WORD="my_super_secret_value"  --name "python_app_$(uuidgen | cut -c1-8)" 221500065327.dkr.ecr.us-east-1.amazonaws.com/my-docker-repo:rearc_image  >> /var/log/user_data.log
              EOF

  tags = {
    Name = "Rearc-Test Instance"
  }
}

resource "aws_lb" "app_lb" {
  name               = "rearc-test-lb"
  load_balancer_type = "application"
  security_groups = [aws_security_group.web_sg.id]
  subnets            =  ["subnet-083e08fcc3fb8489a", "subnet-020c51a8d5fdbf428"]
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = "vpc-0e236649d31a84209" 

 health_check {
    path                = "/"
    port                = "5000"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2

}
}

resource "aws_lb_target_group_attachment" "app_instance_attachment" {
  count            = 2
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_instance[count.index].id
  port             = 5000
}


# HTTPS Listener with the Locally Generated Certificate
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 5000
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.self_signed_cert.arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# IAM Certificate for Locally Generated Self-Signed Certificate
resource "aws_iam_server_certificate" "local_cert" {
  name             = "local-self-signed-cert"
  certificate_body = tls_self_signed_cert.self_signed_cert.cert_pem
  private_key      = tls_private_key.private_key.private_key_pem
}

# Output Public IP
output "public_ip" {
  value = aws_instance.app_instance[*].public_ip
}

output "load_balancer_dns_name" {
  value = aws_lb.app_lb.dns_name
  description = "The DNS name of the Load Balancer"
}

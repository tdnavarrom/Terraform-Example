data "aws_availability_zones" "available" {
    state = "available"
}

resource "random_id" "random" {
  byte_length = 2
}

resource "aws_vpc" "vpc-container" {
  cidr_block       = var.vpc_container
  instance_tenancy = "default"
  
  tags = {
    Name = "vpc-container-${random_id.random.dec}"
  }
}

resource "aws_internet_gateway" "vpc_itg" {
  vpc_id = aws_vpc.vpc-container.id

  tags = {
    Name = "internet_gateway"
  }
}

resource "aws_route_table" "rt-public" {
  vpc_id = aws_vpc.vpc-container.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpc_itg.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.vpc_itg.id
  }

  tags = {
    Name = "Route Table - Internet Gateway"
  }
}

resource "aws_subnet" "mtc_public_subnet" {
  count                   = length(var.public_cidrs)
  vpc_id                  = aws_vpc.vpc-container.id
  cidr_block              = var.public_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "subnet_public_${count.index + 1}"
  }
}

resource "aws_route_table_association" "mtc_public_assoc" {
  count          = length(var.public_cidrs)
  subnet_id      = aws_subnet.mtc_public_subnet[count.index].id
  route_table_id = aws_route_table.rt-public.id
}


resource "aws_eip" "eip_private" {
  count = length(var.public_cidrs)
  vpc      = true
}

resource "aws_nat_gateway" "nat_gateway" {
  count = length(var.public_cidrs)
  allocation_id = aws_eip.eip_private[count.index].id
  subnet_id     = aws_subnet.mtc_public_subnet[count.index].id

  tags = {
    Name = "PUBLIC_NAT-${count.index + 1}"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.vpc_itg]
}

resource "aws_subnet" "mtc_private_subnet" {
  count                   = length(var.private_cidrs)
  vpc_id                  = aws_vpc.vpc-container.id
  cidr_block              = var.private_cidrs[count.index]
  map_public_ip_on_launch = false
  availability_zone       = count.index <= length(var.private_cidrs)/2? data.aws_availability_zones.available.names[0] : data.aws_availability_zones.available.names[1] 

  tags = {
    Name = "subnet_private_${count.index + 1}"
  }
}


resource "aws_route_table" "rt-private" {
  vpc_id = aws_vpc.vpc-container.id
  count = length(var.private_cidrs)

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = count.index <= length(var.private_cidrs)/2? aws_nat_gateway.nat_gateway[0].id : aws_nat_gateway.nat_gateway[1].id
  }

  tags = {
    Name = "Route Table - NAT Gateway"
  }
}

resource "aws_route_table_association" "mtc_private_assoc" {
  count          = length(var.private_cidrs)
  subnet_id      = aws_subnet.mtc_private_subnet[count.index].id
  route_table_id = aws_route_table.rt-private[count.index].id
}


resource "aws_security_group" "allow_web" {
  name        = "allow_web_dev"
  description = "Allow TLS inbound traffic in Dev"
  vpc_id      = aws_vpc.vpc-container.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "SecurityGroup_VPC"
  }
}

resource "aws_instance" "app_server" {
  ami           = var.machine_instances[0]
  instance_type = "t2.micro"
  key_name = var.machine_instances[1]
  count = length(var.private_cidrs)

  vpc_security_group_ids = [aws_security_group.allow_web.id]
  subnet_id              = aws_subnet.mtc_private_subnet[count.index].id

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install software-properties-common -y
                sudo add-apt-repository --yes --update ppa:ansible/ansible
                sudo apt install ansible git -y
                cd /home/ubuntu/
                git clone https://github.com/tdnavarrom/ansible_docker_example
                cd ansible_docker_example/
                ansible-galaxy collection install community.docker
                ansible-playbook -i inventory/hosts site.yml
                EOF

  tags = {
    Name = "intance-${random_id.random.dec}-${count.index}"
  }

  depends_on=[aws_route_table_association.mtc_private_assoc]
}

# resource "aws_acm_certificate" "cert" {
#   domain_name       = "${var.deploy_zone}.tnavarro.pyxinfra.com"
#   validation_method = "DNS"

#   tags = {
#     Environment = var.deploy_zone
#   }

#   lifecycle {
#     create_before_destroy = true
#   }
# }


resource "aws_route53_zone" "main" {
  name = "${var.deploy_zone}.example.com"
}


resource "aws_route53_record" "mtc_record" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.deploy_zone}.example.com"
  type    = "A"


  alias {
    name                   = aws_elb.elb_vpc.dns_name
    zone_id                = aws_elb.elb_vpc.zone_id
    evaluate_target_health = true
  }

}

# Create a new load balancer
resource "aws_elb" "elb_vpc" {
  name               = "vpc-elb-${var.deploy_zone}"
  subnets = aws_subnet.mtc_public_subnet.*.id
  security_groups = [aws_security_group.allow_web.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  #   listener {
  #   instance_port      = 443
  #   instance_protocol  = "http"
  #   lb_port            = 443
  #   lb_protocol        = "https"
  #   ssl_certificate_id = aws_acm_certificate_validation.mtc_ssl_validation.certificate_arn
  # }


  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                   = aws_instance.app_server.*.id
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "terraform-elb"
  }
}

# bastion host security group
resource "aws_security_group" "sg_bastion_host" {
  

  name        = "sg bastion host"
  description = "bastion host security group"
  vpc_id      = aws_vpc.vpc-container.id

  ingress {
    description = "allow SSH"
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

# bastion host ec2 instance
resource "aws_instance" "bastion_host" {
  depends_on = [
    aws_security_group.sg_bastion_host,
  ]
  ami = var.machine_bastion[0]
  instance_type = "t2.micro"
  key_name = var.machine_bastion[1]
  vpc_security_group_ids = [aws_security_group.sg_bastion_host.id]
  subnet_id = aws_subnet.mtc_public_subnet[0].id
  tags = {
      Name = "bastion host"
  }

}
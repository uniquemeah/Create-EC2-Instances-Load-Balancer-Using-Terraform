# Create a VPC
resource "aws_vpc" "alt-terraform-prod" {
  cidr_block       = "${var.vpc_cidr}"
  instance_tenancy = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames    = "true"

  tags = {
    Name = "alt-project"
  }
}

# Create Internet Gateway for VPC
resource "aws_internet_gateway" "prod-igw" {
  vpc_id = aws_vpc.alt-terraform-prod.id

  tags = {
    Name = "main-IGW"
  }
}

# Create Route Table
resource "aws_route_table" "prod-rt" {
  vpc_id = aws_vpc.alt-terraform-prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod-igw.id
  }

  tags = {
    Name = "prod-rt"
  }
}

# Create Public Subnet
resource "aws_subnet" "public-subnet" {
  count = "${length(var.subnet_cidrs)}"
  vpc_id     = aws_vpc.alt-terraform-prod.id
  cidr_block = "${var.subnet_cidrs[count.index]}"
  availability_zone = "${var.availability_zones[count.index]}"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index+1}"
  }
}

# Associate Route table to public subnet
resource "aws_route_table_association" "subnet_association" {
  count = "${length(var.subnet_cidrs)}"
  subnet_id = aws_subnet.public-subnet[count.index].id
  route_table_id = aws_route_table.prod-rt.id
}

# Create Load Balancer security Group
resource "aws_security_group" "load_balancer-sg" {
  name        = "load-balancer-sg"
  vpc_id      = aws_vpc.alt-terraform-prod.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create instance Security Group
resource "aws_security_group" "prod-sg" {
  name        = "allow_traffic"
  description = "Allow traffic"
  vpc_id      = aws_vpc.alt-terraform-prod.id

  ingress {
    description      = "Https"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_groups = [aws_security_group.load_balancer-sg.id]
  }

  ingress {
    description      = "Http"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_groups = [aws_security_group.load_balancer-sg.id]
  }

  ingress {
    description      = "ssh"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prod_sg"
  }
}

# # Create EC2 Instances
resource "aws_instance" "ubuntu-server" {
  count = "${length(var.subnet_cidrs)}"
  ami           = "ami-00874d747dde814fa"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public-subnet[count.index].id
  availability_zone = "${var.availability_zones[count.index]}"
  associate_public_ip_address = true
  key_name = "ubu-key"
  security_groups = [aws_security_group.prod-sg.id]
}

# Copy Instance IP adresses to File.txt
resource "local_file" "instance_ips_file" {
  filename = "host-inventory"
  content  = "${join(", ", aws_instance.ubuntu-server.*.public_ip)}\n"
  depends_on = [aws_instance.ubuntu-server]
}

# Create Target Group
resource "aws_lb_target_group" "production" {
  name     = "prod-lb-tg"
  port     = 80
  target_type = "instance"
  protocol = "HTTP"
  vpc_id   = aws_vpc.alt-terraform-prod.id

  health_check {
     timeout  = 10
     interval = 20
     path    = "/"
     port     = 80
     protocol = "HTTP"
     unhealthy_threshold = 3
     healthy_threshold = 3
  }
}

# Attach Target Group to Instance
resource "aws_lb_target_group_attachment" "target-group-attach" {
  count = "${length(var.subnet_cidrs)}"
  target_group_arn = aws_lb_target_group.production.arn
  target_id        = aws_instance.ubuntu-server[count.index].id
  port             = 80
}

# Create ALB
resource "aws_lb" "production-ALB" {
  # for_each = local.subnet_ids
  name               = "production-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.load_balancer-sg.id]
  subnets            = aws_subnet.public-subnet[*].id
  idle_timeout = 300

  tags = {
    Environment = "production"
  }
}

# listener
resource "aws_lb_listener" "prod-listener" {
  load_balancer_arn = aws_lb.production-ALB.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.production.arn
  }
}

# Create Route53
resource "aws_route53_zone" "hosted_zone" {
   name = "keneunique.tk"

  tags = {
    Environment = "alt-assignment"
  }
}

resource "aws_route53_record" "domain" {
  zone_id = aws_route53_zone.hosted_zone.zone_id
  name    = "terraform-prod.keneunique.tk"
  type    = "A"

  alias {
    name                   = aws_lb.production-ALB.dns_name
    zone_id                = aws_lb.production-ALB.zone_id
    evaluate_target_health = true
  }
}
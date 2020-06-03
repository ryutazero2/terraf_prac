provider "aws" {}

resource "aws_vpc" "myVPC" {
  cidr_block           = "10.5.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "false"
  tags = {
    Name = "myVPC"
  }
}

resource "aws_subnet" "primary" {
  vpc_id     = aws_vpc.myVPC.id
  cidr_block = "10.5.1.0/24"

  map_public_ip_on_launch = true
  tags = {
    Name = "primary"
  }
}

resource "aws_subnet" "secondary" {
  vpc_id     = aws_vpc.myVPC.id
  cidr_block = "10.5.2.0/24"

  map_public_ip_on_launch = true
  tags = {
    Name = "secondary"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.myVPC.id

  tags = {
    Name = "main"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.myVPC.id
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  gateway_id             = aws_internet_gateway.gw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "primary-ass" {
  subnet_id      = aws_subnet.primary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "secondary-ass" {
  subnet_id      = aws_subnet.secondary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb2" {
  name        = "alb2"
  description = "alb to ec2"
  vpc_id      = aws_vpc.myVPC.id

  ingress {
    description = "alb from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb"
  }
}

resource "aws_security_group" "web_server" {
  name        = "web_server"
  description = "Web"
  vpc_id      = aws_vpc.myVPC.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "inbound_mysql" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.mysql.id
  description              = "web_mysqll"


  security_group_id = aws_security_group.web_server.id
}

resource "aws_security_group_rule" "inbound_alb" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = -1
  source_security_group_id = aws_security_group.alb2.id
  description              = "web_alb"
  security_group_id        = aws_security_group.web_server.id
}

resource "aws_security_group" "mysql" {
  name        = "mysql"
  description = "web to mysql"
  vpc_id      = aws_vpc.myVPC.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql"
  }
}
resource "aws_security_group_rule" "inbound_sql" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web_server.id
  description              = "web_mysql"
  security_group_id        = aws_security_group.mysql.id
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "kekehashi.com"
  validation_method = "DNS"

  tags = {
    Environment = "test"
  }

  lifecycle {
    create_before_destroy = true
  }
}



data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer.key_name
  subnet_id              = aws_subnet.primary.id
  vpc_security_group_ids = [aws_security_group.alb2.id]
  #キーペア変えるときはvalueに既存のキーペアを指定する
  tags = {
    Name = "HelloWorld"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41 email@example.com"
}

resource "aws_db_subnet_group" "db_subnet" {
  name       = "main"
  subnet_ids = [aws_subnet.primary.id, aws_subnet.secondary.id]
  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_db_instance" "mysql" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0.19"
  instance_class         = "db.t2.micro"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.id
  name                   = "mydb"
  username               = var.username
  password               = var.password
  vpc_security_group_ids = [aws_security_group.mysql.id]
  parameter_group_name   = "default.mysql8.0"
  identifier             = "mysql"
}

resource "aws_ecr_repository" "web2" {
  name                 = "web2"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs_cluster"
}
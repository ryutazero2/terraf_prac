provider "aws" {}

resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.5.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "false"
  tags = {
    Name = "my_vpc"
  }
}

resource "aws_subnet" "primary" {
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = "ap-northeast-1a"
  cidr_block        = "10.5.1.0/24"

  map_public_ip_on_launch = true
  tags = {
    Name = "primary"
  }
}

resource "aws_subnet" "secondary" {
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = "ap-northeast-1d"
  cidr_block        = "10.5.2.0/24"

  map_public_ip_on_launch = true
  tags = {
    Name = "secondary"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "main"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.my_vpc.id
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
  vpc_id      = aws_vpc.my_vpc.id

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
  vpc_id      = aws_vpc.my_vpc.id
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
  vpc_id      = aws_vpc.my_vpc.id

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

resource "aws_lb_target_group" "ecs-group" {
  name     = "ecs-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id
}

resource "aws_lb" "alb" {
  name               = "alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb2.id]
  subnets            = [aws_subnet.primary.id, aws_subnet.secondary.id]

  enable_deletion_protection = true

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_listener" "httplis" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs-group.arn
  }
}


resource "aws_route53_zone" "dns1" {
  name = var.dns_1
}

resource "aws_route53_record" "alias_name" {
  name    = var.dns_1
  zone_id = aws_route53_zone.dns1.zone_id
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

data "aws_ami" "ecs-ec2" {
  most_recent = true
  owners      = ["591542846629"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.*"]
  }

}

resource "aws_instance" "ecs-task" {
  ami                    = data.aws_ami.ecs-ec2.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.primary.id
  iam_instance_profile   = "ecsInstanceRole"
  key_name               = var.key_pair
  vpc_security_group_ids = [aws_security_group.web_server.id, aws_security_group.mysql.id]
  tags = {
    Name = "ecstask"
  }
  user_data = <<USERDATA
    #!/bin/bash
    sudo bash  -c "echo ECS_CLUSTER="${aws_ecs_cluster.ecs_cluster.name}" > /etc/ecs/ecs.config"
    USERDATA
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

resource "aws_ecs_task_definition" "service" {
  family                = "service"
  container_definitions = file("service.json")

  volume {
    name = "sockets"
    docker_volume_configuration {
      driver = "local"
      scope  = "task"
    }
  }
}

resource "aws_ecs_service" "webapp" {
  name            = "webapp"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.service.id
  desired_count   = 2

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs-group.id
    container_name   = "web"
    container_port   = 80
  }
}
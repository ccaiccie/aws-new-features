data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Subnets
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_subnet" "app" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-app-subnet"
  }
}

resource "aws_subnet" "db" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-db-subnet"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db" {
  subnet_id      = aws_subnet.db.id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web tier: intended HTTPS plus an unintended SSH rule for Network Access Analyzer lab"
  vpc_id      = aws_vpc.lab.id

  # Intended internet access
  ingress {
    description = "Intended HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Unintended internet exposure for Network Access Analyzer to detect
  ingress {
    description = "Unintended SSH from internet (lab finding target)"
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

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "App tier: allows HTTPS from web tier (working path)"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "HTTPS from web tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

resource "aws_security_group" "db_blocked" {
  name        = "${var.project_name}-db-sg"
  description = "DB tier: intentionally missing TCP 5432 ingress rule (blocked path)"
  vpc_id      = aws_vpc.lab.id

  # Intentionally no ingress rule for TCP 5432 so Reachability Analyzer flags ENI_SG_RULES_MISMATCH

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# Disposable EC2 Instances (no SSH key needed; configuration analysis does not send packets)
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-web"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.app.id]

  tags = {
    Name = "${var.project_name}-app"
  }
}

resource "aws_instance" "db" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.db.id
  vpc_security_group_ids = [aws_security_group.db_blocked.id]

  tags = {
    Name = "${var.project_name}-db"
  }
}

# Reachability Analyzer Paths (creating paths does not incur per-analysis charges until analyzed)
resource "aws_ec2_network_insights_path" "working_web_to_app" {
  source           = aws_instance.web.id
  destination      = aws_instance.app.id
  protocol         = "tcp"
  destination_port = 443

  tags = {
    Name = "${var.project_name}-working-web-to-app-443"
  }
}

resource "aws_ec2_network_insights_path" "blocked_app_to_db" {
  source           = aws_instance.app.id
  destination      = aws_instance.db.id
  protocol         = "tcp"
  destination_port = 5432

  tags = {
    Name = "${var.project_name}-blocked-app-to-db-5432"
  }
}

# Optional: Run Reachability Analyzer via Terraform (set run_reachability_analyses = true)
resource "aws_ec2_network_insights_analysis" "working_check" {
  count                    = var.run_reachability_analyses ? 1 : 0
  network_insights_path_id = aws_ec2_network_insights_path.working_web_to_app.id
  wait_for_completion      = true

  tags = {
    Name = "${var.project_name}-working-analysis"
  }
}

resource "aws_ec2_network_insights_analysis" "blocked_check" {
  count                    = var.run_reachability_analyses ? 1 : 0
  network_insights_path_id = aws_ec2_network_insights_path.blocked_app_to_db.id
  wait_for_completion      = true

  tags = {
    Name = "${var.project_name}-blocked-analysis"
  }
}

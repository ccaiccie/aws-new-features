# Two Amazon Linux 2023 test instances, managed with Session Manager (no SSH keys, no inbound SSH).
# The firewall builds out in an AZ only when that AZ has at least one ACTIVE network interface;
# a stopped instance does not count (the AZ shows Standby).

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm" {
  name               = "${var.name}-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name}-ssm-profile"
  role = aws_iam_role.ssm.name
}

resource "aws_security_group" "test" {
  name        = "${var.name}-test"
  description = "Test instances: all egress; optional TCP 8080 from test_client_cidr"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name}-test" }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.test.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "web" {
  count             = var.test_client_cidr == "" ? 0 : 1
  security_group_id = aws_security_group.test.id
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = var.test_client_cidr
}

resource "aws_instance" "public" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.test.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name
  user_data              = <<-EOT
    #!/bin/bash
    mkdir -p /srv/www && echo "public instance (bidirectional)" > /srv/www/index.html
    cd /srv/www && nohup python3 -m http.server 8080 >/dev/null 2>&1 &
  EOT
  tags                   = { Name = "${var.name}-public" }
}

resource "aws_instance" "private" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.test.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  tags                        = { Name = "${var.name}-private" }
}

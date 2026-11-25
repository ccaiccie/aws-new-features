data "aws_ssm_parameter" "al2023_x86" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# EC2 Instance Connect Endpoint is management only, not part of the packet test.
resource "aws_security_group" "ssh_endpoint" {
  name        = "${var.project_name}-ssh-endpoint"
  description = "Permit the private management endpoint to reach the test client"
  vpc_id      = aws_vpc.dev.id

  egress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.dev_app.id]
  }

  tags = local.common_tags
}

# Keep the SSH rule out of the dev-app group: it has an inline egress rule.
resource "aws_security_group" "client_ssh" {
  name        = "${var.project_name}-client-ssh"
  description = "Accept SSH only from the private management endpoint"
  vpc_id      = aws_vpc.dev.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.ssh_endpoint.id]
  }

  tags = local.common_tags
}

resource "aws_ec2_instance_connect_endpoint" "dev" {
  subnet_id          = aws_subnet.dev_private_a.id
  security_group_ids = [aws_security_group.ssh_endpoint.id]
  preserve_client_ip = false
  tags               = local.common_tags
}

resource "aws_instance" "client" {
  ami                         = data.aws_ssm_parameter.al2023_x86.insecure_value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.dev_private_a.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.dev_app.id, aws_security_group.client_ssh.id]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-client" })
}

resource "aws_instance" "server" {
  ami                         = data.aws_ssm_parameter.al2023_x86.insecure_value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.prod_web_a.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.prod_web.id]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  # The standard AL2023 image includes Python; no internet or package install.
  user_data_replace_on_change = true
  user_data = "#cloud-config\n${yamlencode({
    write_files = [
      {
        path        = "/usr/local/bin/context-lab-http.py"
        permissions = "0644"
        content     = file("${path.module}/context-lab-http.py")
      },
      {
        path        = "/etc/systemd/system/context-lab-http.service"
        permissions = "0644"
        content     = file("${path.module}/context-lab-http.service")
      },
    ]
    runcmd = [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "context-lab-http.service"],
    ]
  })}"

  tags = merge(local.common_tags, { Name = "${var.project_name}-server" })
}

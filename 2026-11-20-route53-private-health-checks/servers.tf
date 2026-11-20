# Two web servers in different AZs with fixed private IPs (.10 in subnet 1 and 2).
# Python's built-in HTTP server answers GET /health with 200 and body "OK".
# Amazon Linux 2023 ships python3, so nothing is downloaded (no internet in this VPC).

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  web_user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    mkdir -p /srv/www
    echo "OK $(hostname)" > /srv/www/${trimprefix(var.health_path, "/")}
    echo "hello from $(hostname)" > /srv/www/index.html
    cat > /etc/systemd/system/labweb.service <<'UNIT'
    [Unit]
    Description=Lab web server for Route 53 private health checks
    After=network-online.target
    [Service]
    ExecStart=/usr/bin/python3 -m http.server ${var.app_port} --directory /srv/www
    Restart=always
    [Install]
    WantedBy=multi-user.target
    UNIT
    systemctl daemon-reload
    systemctl enable --now labweb.service
  EOT
}

resource "aws_instance" "web" {
  count                  = 2 # 0 = primary (AZ 1), 1 = secondary (AZ 2)
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[count.index].id
  private_ip             = count.index == 0 ? local.primary : local.standby
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data              = local.web_user_data

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "${var.name}-${count.index == 0 ? "primary" : "secondary"}" }
}

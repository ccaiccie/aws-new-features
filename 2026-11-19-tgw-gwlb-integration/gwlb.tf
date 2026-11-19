# Gateway Load Balancer, GENEVE target group, optional appliances, and the
# VPC endpoint service that the transit gateway network function attachment connects to.

resource "aws_lb" "gwlb" {
  name                             = "${var.name}-gwlb"
  load_balancer_type               = "gateway"
  subnets                          = aws_subnet.appliance[*].id
  enable_cross_zone_load_balancing = false
}

resource "aws_lb_target_group" "appliances" {
  name        = "${var.name}-appliances"
  port        = 6081
  protocol    = "GENEVE"
  vpc_id      = aws_vpc.security.id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = tostring(var.health_check_port)
  }
}

resource "aws_lb_listener" "gwlb" {
  load_balancer_arn = aws_lb.gwlb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.appliances.arn
  }
}

resource "aws_security_group" "appliance" {
  name        = "${var.name}-appliance"
  description = "GENEVE from the GWLB and health checks"
  vpc_id      = aws_vpc.security.id

  ingress {
    description = "GENEVE"
    from_port   = 6081
    to_port     = 6081
    protocol    = "udp"
    cidr_blocks = [var.security_vpc_cidr]
  }

  ingress {
    description = "GWLB health check"
    from_port   = var.health_check_port
    to_port     = var.health_check_port
    protocol    = "tcp"
    cidr_blocks = [var.security_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "appliance" {
  count                  = var.appliance_ami_id == "" ? 0 : length(var.azs)
  ami                    = var.appliance_ami_id
  instance_type          = var.appliance_instance_type
  subnet_id              = aws_subnet.appliance[count.index].id
  vpc_security_group_ids = [aws_security_group.appliance.id]
  source_dest_check      = false
  tags                   = { Name = "${var.name}-appliance-${count.index}" }
}

resource "aws_lb_target_group_attachment" "appliance" {
  count            = length(aws_instance.appliance)
  target_group_arn = aws_lb_target_group.appliances.arn
  target_id        = aws_instance.appliance[count.index].id
}

# The endpoint service that "fronts the firewall deployment".
# The transit gateway creates one GWLB endpoint per selected AZ against this service.
resource "aws_vpc_endpoint_service" "gwlb" {
  acceptance_required        = var.acceptance_required
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]
  tags                       = { Name = "${var.name}-gwlb-svc" }
}

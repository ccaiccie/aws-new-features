# ------------------------------------------------------------------------------
# Part 1: Minimal VPC, Public ALB (Fixed-Response Backend) & CloudFront
# ------------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.90.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.prefix}-vpc" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
}

resource "aws_subnet" "pub_a" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.90.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "pub_b" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.90.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.pub_b.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_security_group" "alb" {
  name        = "${var.prefix}-alb-sg"
  description = "Allow HTTP 80 into lab ALB"
  vpc_id      = aws_vpc.lab.id

  ingress {
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
}

resource "aws_lb" "lab" {
  name               = "${var.prefix}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.pub_a.id, aws_subnet.pub_b.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lab.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"status\":\"allowed\",\"origin\":\"waf-shield-lab-alb\"}"
      status_code  = "200"
    }
  }
}

# ------------------------------------------------------------------------------
# Part 2A: Global Web ACL (CLOUDFRONT, us-east-1) + CloudFront Distribution
# ------------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "cf_blocked" {
  provider           = aws.us_east_1
  name               = "${var.prefix}-cf-ipset"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.example_blocked_cidrs
}

resource "aws_wafv2_web_acl" "cf_global" {
  provider = aws.us_east_1
  name     = "${var.prefix}-cf-global-acl"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "BlockExampleIpSet"
    priority = 10
    action {
      block {}
    }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.cf_blocked.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cfBlockIpSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "CustomHeaderRule"
    priority = 20
    action {
      dynamic "count" {
        for_each = var.custom_rule_count_mode ? [1] : []
        content {}
      }
      dynamic "block" {
        for_each = var.custom_rule_count_mode ? [] : [1]
        content {}
      }
    }
    statement {
      byte_match_statement {
        positional_constraint = "EXACTLY"
        search_string         = "true"
        field_to_match {
          single_header {
            name = "x-lab-block"
          }
        }
        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cfCustomHeader"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIp"
    priority = 30
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_5min
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cfRateLimit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedCommonRuleSet"
    priority = 40
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cfManagedCommon"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "cfGlobalWebAcl"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_log_group" "cf_waf" {
  provider          = aws.us_east_1
  name              = "aws-waf-logs-${var.prefix}-cf" # Required prefix: aws-waf-logs-
  retention_in_days = 7
}

resource "aws_wafv2_web_acl_logging_configuration" "cf_waf" {
  provider                = aws.us_east_1
  log_destination_configs = [aws_cloudwatch_log_group.cf_waf.arn]
  resource_arn            = aws_wafv2_web_acl.cf_global.arn
}

resource "aws_cloudfront_distribution" "lab" {
  enabled         = true
  comment         = "WAF & Shield lab distribution fronting ALB"
  web_acl_id      = aws_wafv2_web_acl.cf_global.arn
  price_class     = "PriceClass_100"

  origin {
    domain_name = aws_lb.lab.dns_name
    origin_id   = "lab-alb-origin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "lab-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = true
      headers      = ["x-lab-block"]
      cookies { forward = "none" }
    }
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ------------------------------------------------------------------------------
# Part 2B: Separate Regional Web ACL (REGIONAL) Associated With the ALB
# ------------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "alb_blocked" {
  name               = "${var.prefix}-alb-ipset"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.example_blocked_cidrs
}

resource "aws_wafv2_web_acl" "alb_regional" {
  name  = "${var.prefix}-alb-regional-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "BlockExampleIpSet"
    priority = 10
    action { block {} }
    statement {
      ip_set_reference_statement { arn = aws_wafv2_ip_set.alb_blocked.arn }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "albBlockIpSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "CustomHeaderRule"
    priority = 20
    action {
      dynamic "count" {
        for_each = var.custom_rule_count_mode ? [1] : []
        content {}
      }
      dynamic "block" {
        for_each = var.custom_rule_count_mode ? [] : [1]
        content {}
      }
    }
    statement {
      byte_match_statement {
        positional_constraint = "EXACTLY"
        search_string         = "true"
        field_to_match { single_header { name = "x-lab-block" } }
        text_transformation { priority = 0; type = "LOWERCASE" }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "albCustomHeader"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIp"
    priority = 30
    action { block {} }
    statement {
      rate_based_statement { limit = var.rate_limit_5min; aggregate_key_type = "IP" }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "albRateLimit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedCommonRuleSet"
    priority = 40
    override_action { none {} }
    statement {
      managed_rule_group_statement { name = "AWSManagedRulesCommonRuleSet"; vendor_name = "AWS" }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "albManagedCommon"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "albRegionalWebAcl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.lab.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_regional.arn
}

resource "aws_cloudwatch_log_group" "alb_waf" {
  name              = "aws-waf-logs-${var.prefix}-alb" # Required prefix: aws-waf-logs-
  retention_in_days = 7
}

resource "aws_wafv2_web_acl_logging_configuration" "alb_waf" {
  log_destination_configs = [aws_cloudwatch_log_group.alb_waf.arn]
  resource_arn            = aws_wafv2_web_acl.alb_regional.arn
}

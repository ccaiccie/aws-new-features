data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
}

# ---------------------------------------------------------------- GuardDuty: detect
# Foundational sources (CloudTrail management events, VPC Flow Logs, Route 53 Resolver
# DNS query logs) start immediately as independent streams; nothing to enable in your account.
resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency
}

# ---------------------------------------------------------------- Macie: discover
resource "aws_macie2_account" "this" {
  finding_publishing_frequency = var.finding_publishing_frequency
  status                       = "ENABLED"
}

resource "aws_s3_bucket" "lab_data" {
  bucket_prefix = "${var.name_prefix}-data-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lab_data" {
  bucket                  = aws_s3_bucket.lab_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Fake test data only: a well-known test card number and example.com addresses.
resource "aws_s3_object" "fake_customers" {
  bucket       = aws_s3_bucket.lab_data.id
  key          = "exports/customers-test.csv"
  content_type = "text/csv"
  content      = <<-CSV
    name,employee id,email,phone,credit_card_number,expiration
    Jane Example,EMP-100001,jane.example@example.com,+1-206-555-0100,4111 1111 1111 1111,12/30
    John Sample,EMP-100002,john.sample@example.com,+1-206-555-0101,5555 5555 5555 4444,11/29
  CSV
}

# Custom data identifier: regex + keyword + proximity (here, a made-up employee ID format).
resource "aws_macie2_custom_data_identifier" "employee_id" {
  name                   = "${var.name_prefix}-employee-id"
  description            = "Lab: internal employee IDs like EMP-123456"
  regex                  = "EMP-[0-9]{6}"
  keywords               = ["employee id"]
  maximum_match_distance = 50
  depends_on             = [aws_macie2_account.this]
}

resource "aws_macie2_classification_job" "lab" {
  count       = var.create_macie_job ? 1 : 0
  name        = "${var.name_prefix}-one-time"
  description = "Lab: one-time sensitive data discovery job on the lab bucket"
  job_type    = "ONE_TIME"

  custom_data_identifier_ids = [aws_macie2_custom_data_identifier.employee_id.id]

  s3_job_definition {
    bucket_definitions {
      account_id = local.account_id
      buckets    = [aws_s3_bucket.lab_data.id]
    }
  }

  depends_on = [aws_macie2_account.this, aws_s3_object.fake_customers]
}

# ---------------------------------------------------------------- Security Hub CSPM: aggregate
resource "aws_securityhub_account" "this" {
  enable_default_standards  = false
  auto_enable_controls      = true
  control_finding_generator = "SECURITY_CONTROL"
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# Normally unnecessary: GuardDuty and Macie integrations turn on automatically.
resource "aws_securityhub_product_subscription" "macie" {
  count       = var.enable_macie_product_subscription ? 1 : 0
  product_arn = "arn:${local.partition}:securityhub:${local.region}::product/aws/macie"
  depends_on  = [aws_securityhub_account.this, aws_macie2_account.this]
}

# ---------------------------------------------------------------- Optional: delegated administrator
resource "aws_guardduty_organization_admin_account" "this" {
  count            = var.delegated_admin_account_id == "" ? 0 : 1
  admin_account_id = var.delegated_admin_account_id
  depends_on       = [aws_guardduty_detector.this]
}

resource "aws_macie2_organization_admin_account" "this" {
  count            = var.delegated_admin_account_id == "" ? 0 : 1
  admin_account_id = var.delegated_admin_account_id
  depends_on       = [aws_macie2_account.this]
}

resource "aws_securityhub_organization_admin_account" "this" {
  count            = var.delegated_admin_account_id == "" ? 0 : 1
  admin_account_id = var.delegated_admin_account_id
  depends_on       = [aws_securityhub_account.this]
}

# Hospital System Security: IAM Role & Least-Privilege DB Credentials


# 1. Generate a separate password for the Public Patient Portal DB User (Least Privilege)
resource "random_password" "public_db_password" {
  length  = 16
  special = false
}

# 2. Store the Public DB User password securely in AWS SSM Parameter Store
resource "aws_ssm_parameter" "public_db_password_param" {
  name        = "/sme-project/database/public_user_password"
  description = "Password for restricted Public Patient Portal MySQL user"
  type        = "SecureString"
  value       = random_password.public_db_password.result
}

# 3. Create an IAM Role for the EC2 Web Server
resource "aws_iam_role" "web_server_ssm_role" {
  name = "sme-hospital-web-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "SME-Hospital-Web-SSM-Role"
  }
}

# 4. IAM Policy allowing EC2 to read ONLY our two Database Passwords from SSM (tfsec compliant)
resource "aws_iam_role_policy" "web_server_ssm_policy" {
  name = "sme-hospital-web-ssm-policy"
  role = aws_iam_role.web_server_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.db_password_param.arn,
          aws_ssm_parameter.public_db_password_param.arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances"]
        Resource = [aws_db_instance.sme_database.arn]
      }
    ]
  })
}

# 5. Create an IAM Instance Profile to attach this Role to the EC2 Web Server
resource "aws_iam_instance_profile" "web_server_profile" {
  name = "sme-hospital-web-instance-profile"
  role = aws_iam_role.web_server_ssm_role.name
}

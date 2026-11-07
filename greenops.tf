# GreenOps Module: Automated Server Shutdown & Startup for Cost & Carbon Saving

# 1. IAM Role for AWS EventBridge Scheduler
resource "aws_iam_role" "greenops_scheduler_role" {
  name = "sme-greenops-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "SME-GreenOps-IAM-Role"
  }
}

# 2. IAM Policy allowing Scheduler to Stop/Start ONLY our SME EC2 Instances (tfsec compliant)
resource "aws_iam_role_policy" "greenops_scheduler_policy" {
  name = "sme-greenops-scheduler-policy"
  role = aws_iam_role.greenops_scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:StartInstances"
        ]
        Resource = [
          aws_instance.web_server.arn,
          aws_instance.bastion_host.arn
        ]
      }
    ]
  })
}


# 3. GreenOps Rule 1: Auto-Shutdown Servers at 8:00 PM (Sri Lanka Time) after Clinic Hours
resource "aws_scheduler_schedule" "sme_night_shutdown" {
  name       = "sme-greenops-night-shutdown"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  # Runs at 8:00 PM (20:00) every day according to Sri Lanka Timezone
  schedule_expression          = "cron(0 20 * * ? *)"
  schedule_expression_timezone = "Asia/Colombo"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.greenops_scheduler_role.arn

    input = jsonencode({
      InstanceIds = [
        aws_instance.web_server.id,
        aws_instance.bastion_host.id
      ]
    })
  }
}


# 4. GreenOps Rule 2: Auto-Start Servers at 8:00 AM (Sri Lanka Time)
resource "aws_scheduler_schedule" "sme_morning_startup" {
  name       = "sme-greenops-morning-startup"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  # Runs at 8:00 AM (08:00) every day according to Sri Lanka Timezone
  schedule_expression          = "cron(0 8 * * ? *)"
  schedule_expression_timezone = "Asia/Colombo"

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.greenops_scheduler_role.arn

    input = jsonencode({
      InstanceIds = [
        aws_instance.web_server.id,
        aws_instance.bastion_host.id
      ]
    })
  }
}






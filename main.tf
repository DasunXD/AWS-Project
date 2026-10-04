terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
  
  # S3 bucket for for Github Actions to store the Terraform state file
  backend "s3" {
    bucket = "sme-terraform-state-dasun-2026" 
    key    = "sme/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

#creating a VPC with CIDR block
resource "aws_vpc" "my_first_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "SME-Project-VPC"
  }
} 

#creating a public subnet in the VPC
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.my_first_vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "SME-Public-Subnet"
  }
}

#Creating an Internet Gateway and associating it with the VPC
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_first_vpc.id

  tags = {
    Name = "SME-Internet-Gateway"
  }
}

#creating a route table and associating it with the public subnet to allow internet access
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_first_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "SME-Public-Route-Table"
  }
}

#Implementing Secuirity Group to allow HTTP and SSH traffic  
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
} 

resource "aws_security_group" "allow_web_ssh" {
  name        = "sme-web-ssh-sg"
  description = "Allow Web and SSH incoming traffic"
  vpc_id      = aws_vpc.my_first_vpc.id

  ingress {
    description = "HTTP Web Traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH for Admin Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SME-Web-Security-Group"
  }
}

#Implementing Private Subnet and Route Table for Private Subnet 
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.my_first_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "SME-Private-Subnet"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.my_first_vpc.id

  
  
  tags = {
    Name = "SME-Private-Route-Table"
  }
}

resource "aws_route_table_association" "private_rt_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

#create EC2 instance in public subnet with user data to install Apache web server and create a simple HTML page
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.allow_web_ssh.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Welcome to SME Project Web Server! Built with Terraform.</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "SME-Web-Server"
  }
}

output "web_server_public_ip" {
  value = aws_instance.web_server.public_ip
}

# Creating Security Group for Database to allow traffic from Web Server AND Bastion Host
resource "aws_security_group" "db_sg" {
  name        = "sme-db-sg"
  description = "Allow MySQL traffic from Web Server and Bastion Host"
  vpc_id      = aws_vpc.my_first_vpc.id

  # Inbound Rules 1: Allow MySQL traffic from the Web Server
  ingress {
    description     = "MySQL access from Web Server"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_web_ssh.id]
  }

  # Inbound Rules 2: Allow MySQL traffic from the Bastion Host (NEW)
  ingress {
    description     = "MySQL access from Bastion Host for Admin"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Outbound Rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SME-DB-Security-Group"
  }
}

# Creating a second private subnet in a different availability zone for high availability
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.my_first_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b" #setting a different availability zone for high availability

  tags = {
    Name = "SME-Private-Subnet-2"
  }
}

# 3. Creating a DB Subnet Group for RDS to use both private subnets for high availability
resource "aws_db_subnet_group" "sme_db_subnet_group" {
  name       = "sme-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id] # connecting both private subnets for high availability

  tags = {
    Name = "SME-DB-Subnet-Group"
  }
}

# Create a random, highly secure password automatically
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store the password securely in AWS Systems Manager (SSM) Parameter Store
resource "aws_ssm_parameter" "db_password_param" {
  name        = "/sme-project/database/password"
  description = "Master password for SME RDS database"
  type        = "SecureString"
  value       = random_password.db_password.result
}

# 4. Creating the RDS Database Instance (Updated with DevSecOps)
resource "aws_db_instance" "sme_database" {
  allocated_storage      = 20
  max_allocated_storage  = 0
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  identifier             = "sme-project-db"
  username               = "admin"
  password               = random_password.db_password.result # Fetching secure password dynamically
  db_subnet_group_name   = aws_db_subnet_group.sme_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  storage_encrypted      = true # AWS KMS Encryption Enabled (Zero Cost)

  tags = {
    Name = "SME-Private-Database-Encrypted"
  }
}


# FinOps: AWS Budgets to monitor and control SME cloud costs (Zero Cost)
resource "aws_budgets_budget" "sme_cost_budget" {
  name              = "sme-monthly-budget"
  budget_type       = "COST"
  limit_amount      = "10.0" 
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-07-01_00:00"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80 
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["ddilhara088@gmail.com"] 
  }
}


# Creating Security Group for Bastion Host
resource "aws_security_group" "bastion_sg" {
  name        = "sme-bastion-sg"
  description = "Allow SSH access to Bastion Host for Admin"
  vpc_id      = aws_vpc.my_first_vpc.id

  ingress {
    description = "SSH Access for Admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    # tfsec:ignore:aws-vpc-no-public-ingress-sgr
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SME-Bastion-Security-Group"
  }
}

# Creating the Bastion Host EC2 Instance in the Public Subnet
resource "aws_instance" "bastion_host" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "SME-Bastion-Host"
  }
}

# Output the Bastion Host IP to easily find it
output "bastion_host_public_ip" {
  value = aws_instance.bastion_host.public_ip
}



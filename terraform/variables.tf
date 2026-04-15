# variables.tf

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"  # Change to your region
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_a_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_b_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_a_cidr" {
  type    = string
  default = "10.0.3.0/24"
}

variable "private_subnet_b_cidr" {
  type    = string
  default = "10.0.4.0/24"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "asg_min_size" {
  type    = number
  default = 1
}

variable "asg_max_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  type    = number
  default = 1
}

variable "db_name" {
  type    = string
  default = "tododb"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "alarm_email" {
  description = "Your email — AWS will send a confirmation, click it or alarms won't work"
  type        = string
  default     = "hatimabizer01@gmail.com"
}

variable "suffix" {
  description = "Suffix for resource names to avoid conflicts"
  type        = string
  default     = "-v4"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be one of: dev, prod."
  }
}

variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
}

variable "twitch_client_id" {
  type = string
}

variable "twitch_client_secret" {
  type = string
}

variable "domain_api_name" {
  type = string
}

variable "dynamodb_table_auth_states" {
  type = string
}

variable "dynamodb_table_users" {
  type = string
}
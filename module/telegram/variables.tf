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

variable "telegram_bot_token" {
  type      = string
  sensitive = true
}

variable "twitch_redirect_url" {
  type = string
}

variable "twitch_client_id" {
  type = string
}

variable "domain_api_name" {
  type = string
}

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

variable "namecheap_username" {
  type      = string
  sensitive = true
}

variable "namecheap_api_key" {
  type      = string
  sensitive = true
}

variable "domain" {
  type = string
}

resource "aws_cognito_user_pool" "main" {
  name = var.user_pool_name

  # Use email as username
  username_attributes      = ["email"]
  
  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
    temporary_password_validity_days = 7
  }

  # MFA configuration
  mfa_configuration = "OPTIONAL"
  
  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Required attributes for sign-up
  schema {
    name                = "name"  # Full name attribute
    attribute_data_type = "String"
    mutable             = true
    required            = true
    
    string_attribute_constraints {
      min_length = 2
      max_length = 100
    }
  }

  # Optional attributes
  schema {
    name                = "phone_number"
    attribute_data_type = "String"
    mutable             = true
    required            = false
  }
  
  schema {
    name                = "birthdate"
    attribute_data_type = "String"
    mutable             = true
    required            = false
  }

  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }

  # Admin create user config
  admin_create_user_config {
    allow_admin_create_user_only = false
    
    invite_message_template {
      email_message = "Your username is {username} and temporary password is {####}. Please login to change your password."
      email_subject = "Your temporary password for ${var.app_name}"
      sms_message   = "Your username is {username} and temporary password is {####}"
    }
  }
  
  # Enable Lambda triggers if needed
  # lambda_config {
  #   pre_sign_up         = var.pre_sign_up_lambda_arn
  #   post_confirmation   = var.post_confirmation_lambda_arn
  #   pre_authentication  = var.pre_authentication_lambda_arn
  # }

  # Device configuration
  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }

  # Custom domains configuration (Optional)
  # domain = var.custom_domain_name

  # Tags
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# User Pool Client with callback URLs
resource "aws_cognito_user_pool_client" "client" {
  name                                 = "${var.app_name}-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  
  # Generate secret for server-side apps
  generate_secret                      = var.generate_client_secret
  
  # Prevent user existence errors
  prevent_user_existence_errors        = "ENABLED"
  
  # Auth flows
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
  
  # Token validity
  refresh_token_validity               = 30
  access_token_validity                = 1
  id_token_validity                    = 1
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
  
  # OAuth settings
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["phone", "email", "openid", "profile", "aws.cognito.signin.user.admin"]
  
  # Callback and logout URLs
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  
  # Enable token revocation
  enable_token_revocation              = true
  
  # Supported identity providers
  supported_identity_providers         = ["COGNITO"]
}

# Optional: User pool domain
resource "aws_cognito_user_pool_domain" "main" {
  domain          = var.cognito_domain_prefix
  user_pool_id    = aws_cognito_user_pool.main.id
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "user_pool_name" {
  description = "The name of the user pool"
  type        = string
  default     = "app-user-pool"
}

variable "app_name" {
  description = "The name of the application"
  type        = string
  default     = "my-app"
}

variable "environment" {
  description = "Environment (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "my-project"
}

variable "callback_urls" {
  description = "List of allowed callback URLs for the identity providers"
  type        = list(string)
  default     = ["https://example.com/callback", "http://localhost:3000/callback"]
}

variable "logout_urls" {
  description = "List of allowed logout URLs for the identity providers"
  type        = list(string)
  default     = ["https://example.com/logout", "http://localhost:3000/logout"]
}

variable "cognito_domain_prefix" {
  description = "The prefix for the Cognito hosted UI domain"
  type        = string
  default     = "my-app-login"
}

variable "generate_client_secret" {
  description = "Boolean flag to generate client secret"
  type        = bool
  default     = true
}

variable "sms_external_id" {
  description = "External ID used in IAM role trust relationships for SMS"
  type        = string
  default     = "cognito-sms-role"
}

variable "sns_caller_arn" {
  description = "ARN of the IAM role authorized to publish SMS notifications"
  type        = string
  default     = ""
}

# Outputs
output "user_pool_id" {
  description = "ID of the user pool"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  description = "ID of the user pool client"
  value       = aws_cognito_user_pool_client.client.id
}

output "user_pool_domain" {
  description = "Domain of the user pool"
  value       = "https://${var.cognito_domain_prefix}.auth.${var.aws_region}.amazoncognito.com"
}

output "hosted_ui_url" {
  description = "URL of the hosted UI for sign-in"
  value       = "https://${var.cognito_domain_prefix}.auth.${var.aws_region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.client.id}&response_type=code&scope=email+openid+phone+profile&redirect_uri=${urlencode(var.callback_urls[0])}"
}
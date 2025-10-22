# Root Terragrunt configuration for remote state & common inputs.

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket        = "ys-terragrunt-terraform-state-bucket"
    key           = "${path_relative_to_include()}/terraform.tfstate"
    use_lockfile  = true
    region        = "us-east-1"
    encrypt       = true
  }
}

# Common tags and shared inputs
inputs = { 
  name_prefix   = "ys"
  region        = "us-east-1"
  environment   = "staging"
  tags = {
    Environment = "staging"
    Project     = "devops-exercise"
    ManagedBy   = "Terragrunt"
  }
}


# Configure the AWS provider
generate "provider" {
  path = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
provider "aws" {
  region = "us-east-1"
}
EOF
}

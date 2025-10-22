# Include the root terragrunt.hcl file to inherit its settings (remote_state, common inputs).
include "root" {
  path = find_in_parent_folders()
}

dependency "network" {
  config_path   = "../network"
  mock_outputs  = {
      vpc_id                      = "mocked-output"
      public_subnet_ids_for_alb   = ["mocked-output"]
      private_subnet_ids_for_asg  = ["mocked-output"]
  }
  mock_outputs_allowed_terraform_commands = ["plan", "init", "validate"]
}

terraform {
  source = "../../../modules/ec2-app"
}

inputs = {
  vpc_id                      = dependency.network.outputs.vpc_id
  public_subnet_ids_for_alb   = dependency.network.outputs.public_subnet_ids_for_alb
  private_subnet_ids_for_asg  = dependency.network.outputs.private_subnet_ids_for_asg

  # Fill this with the AMI ID produced by packer build (see README.md)
  ami_id                      = "ami-XXX"

  instance_type               = "t3.micro"
  create_ssh_key              = true                          // Terraform will generate SSH key pair
  ssh_key_name                = null                          // Used when key exists and create_ssh_key=false
  ssh_ingress_cidrs           = ["0.0.0.0/0"]                 // tighten this for SSH access in production

  app_port                    = 80
  health_check_path           = "/"

  # Optional TLS
  domain_name                 = "XXX"                         // provide custom managed domain_name
  route53_zone_id             = "XXX"                         // provide custom managed hosted zone id
  enable_https                = false                         // change to true when the above values are filled in
  
  # Optional Bastion
  enable_bastion              = true
  bastion_ingress_cidr        = "0.0.0.0/0"                   // tighten this for SSH access in production
  
  site_title                  = "Staging Nginx"
  message                     = "Hello from ASG in private subnets"
}

# Include the root terragrunt.hcl file to inherit its settings (remote_state, common inputs).
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/vpc"
}

inputs = {
  vpc_cidr       = "172.16.0.0/16"
  azs            = ["us-east-1a", "us-east-1b"]
  subnets_per_az = 2                                // => two public + two private per AZ (total 8 subnets)
}

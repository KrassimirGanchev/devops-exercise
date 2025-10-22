packer {
  required_version = ">= 1.10.0"
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = "~> 1"
      source = "github.com/hashicorp/ansible"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

source "amazon-ebs" "al2023" {
  region                  = var.region
  instance_type           = "t3.micro"
  ssh_username            = "ec2-user"
  ami_name                = "al2023-nginx-pack-fry-{{timestamp}}"
  associate_public_ip_address = true
  ebs_optimized = true

  launch_block_device_mappings {
    device_name = "/dev/xvda"
    volume_size = "20"
    volume_type = "gp3"
    iops = 3000
    throughput = 125
    delete_on_termination = true
  }

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      architecture        = "x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["137112412989"] # Amazon
    most_recent = true
  }

}

build {
  name    = "al2023-nginx-pack-fry"
  sources = ["source.amazon-ebs.al2023"]

  

  provisioner "shell" {
    inline = [
      "sudo dnf -y update",
      "sudo dnf -y install python3-pip",
      "sudo pip install ansible",
      "ansible-galaxy collection install community.general",
      "sudo dnf install -y amazon-ssm-agent",
      "sudo systemctl enable --now amazon-ssm-agent"
    ]
  }

  # Copy entire ansible tree
  provisioner "file" {
    source      = "../ansible"
    destination = "/tmp/ansible"
  }

  # Run PACK role (installs nginx, places fry artifacts & systemd unit)
  provisioner "ansible-local" {
    playbook_file = "../ansible/pack.yml"
    command       = "ANSIBLE_CONFIG=/tmp/ansible/ansible.cfg ansible-playbook"
  }
}

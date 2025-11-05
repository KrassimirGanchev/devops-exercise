# DevOps exercises: AWS VPC + EC2 App (Staging) + Helm

This repo contains three deliverables:

1. **AWS VPC Exercise** — A Terraform module (used via Terragrunt) that creates a staging VPC:
   - CIDR **172.16.0.0/16**
   - **2 Availability Zones**
   - **Two public and two private subnets per AZ** (total 8 subnets)
   - **Internet Gateway**, **NAT** per AZ
   - **Route tables** (public & per‑AZ private with NAT)
   - **VPC Endpoints**: S3 **gateway** endpoint and **interface** endpoints for **SSM**, **SSM Messages**, **EC2 Messages** (so EC2s in private subnets can use SSM without internet)

2. **A Small EC2 App** — AMI built with **Packer** + **Ansible** using a **pack/fry idiom**:
   - **Pack** role bakes **nginx** and **Amazon SSM agent** and places a **systemd** unit `fry.service`
   - **Fry** role (runs at boot) renders a static HTML page with variables injected via **user data**
   - Terraform stack (Terragrunt) creates:
     - **Launch Template**
     - **Auto Scaling Group** with **2 EC2 instances** in **private subnets**
     - **Application Load Balancer (ALB)** in public subnets + **Target Group**
     - **Bastion host** for SSH access to private instances (optional)
     - **Security Groups** (ALB <-> instances, SSH)
     - **IAM Instance Profile** with SSM and CloudWatch agent policies
     - **Automated SSH key generation** and management (optional)
     - Optional HTTPS via **ACM** (set `enable_https`, `domain_name`, `route53_zone_id`)

3. **Helm Chart (Nginx + Ingress)** — A Kubernetes application deployment:
   - **Nginx deployment** with configurable replicas
   - **Service** (ClusterIP)
   - **Ingress resource** for external access
   - Supports both local testing (minikube) and AWS deployment
   - Configurable for ALB (optional) or NGINX ingress controller (used)

---

## 0) Prereqs

- Terraform ≥ 1.5, Terragrunt > 0.93, Packer ≥ 1.10, Ansible, AWS CLI
- **For Helm/Kubernetes**: kubectl, Helm ≥ 3.0, Docker, minikube (or kind) for local testing
- An AWS account with permissions to create VPC, EC2, ALB, IAM, EKS, S3, ACM (optional), Route53 (Optional).

---

## 1) Build the AMI (Packer + Ansible)
The pack role installs nginx and drops a fry.service that runs at boot. The fry role renders /usr/share/nginx/html/index.html using variables provided at instance launch (via user data).

Build
```bash
cd packer
packer init .
packer build ami-al2023-nginx.pkr.hcl
```

When it finishes, note the AMI ID and place it into:
live/staging/ec2-app/terragrunt.hcl  (ami_id = "ami-XXXXXXXX")

---

## 2) Network (VPC) — with Terragrunt

> **Assumption:** We create **2 public + 2 private subnets per AZ**. Each AZ gets its own NAT Gateway; private route tables in each AZ default route to that NAT. S3 is a **gateway** endpoint; SSM endpoints are **interface** endpoints reachable inside the VPC.

Outputs to note and be used further:

vpc_id
public_subnet_ids_for_alb — first public subnet in each AZ (for ALB)
private_subnet_ids_for_asg — first private subnet in each AZ (for ASG)

---

## 3) EC2 App (ALB + ASG in private subnets)

Configure:
Edit live/staging/ec2-app/terragrunt.hcl:
•	Set ami_id to the AMI from Packer.
•	Optional: TLS data for HTTPS (with custom domain)
•	Set ssh_ingress_cidrs to your IP for SSH.

What happens:
•	ALB is placed in the public subnets (one per AZ) and exposes HTTP (and HTTPS if you set ACM).
•	ASG of 2 EC2s launches in private subnets (one per AZ).
•	User data writes /etc/fry/vars.json with your site_title and message, then starts fry.service which renders the page and starts nginx.
•	SSM works even in private subnets due to the VPC Interface Endpoints.

Find your app: output alb_dns_name (e.g., http://staging-nginx-alb-xxxxxxxx.us-east-1.elb.amazonaws.com/)

SSH: Use SSM Session Manager or SSH via bastion. Security group allows SSH from ssh_ingress_cidrs.

TLS (optional): If you supply domain_name, route53_zone_id and enable_https=true, port 443 listener forwards to the target group, and HTTP (80) redirects to HTTPS.

---

## 4) Bring up the infra

```bash
cd live
terragrunt run --all --backend-bootstrap init
terragrunt run --all -- plan
terragrunt run --all -- apply
```
---

## Notes

- Adjust CIDR ranges, instance types, and other parameters in the Terragrunt configurations as needed.
- Subnets per AZ: The VPC module creates two public and two private subnets per AZ to align with the requirement and to enable multi‑AZ spreading for future workloads (e.g., separate app/data subnets).
- NAT per AZ: Each AZ has its own NAT for high availability; all private subnets in that AZ route to their local NAT.
- Endpoints:
o S3 is a gateway endpoint attached to the private route tables.
o SSM/SSM Messages/EC2 Messages are interface endpoints with a dedicated SG that allows 443 from the VPC CIDR.
- Pack/Fry idiom:
o Pack: bake stable OS deps (nginx, ansible, systemd unit).
o Fry: apply dynamic config at boot (site title/message) via user data → /etc/fry/vars.json → fry.service runs ansible-playbook.
- Private instances: The ASG runs in private subnets; outbound Internet goes via NAT to fetch packages/updates if needed.

## Clean up

These resources incur cost (ALB, NAT Gateways!). When done, clean up:

```bash
cd live/staging/
terragrunt run --all destroy
```
---



## 4) Helm Chart (Nginx + Ingress)

### Overview
This Helm chart deploys an NGINX deployment with a service and an ingress resource. The ingress can be configured to use either the AWS Load Balancer Controller (ALB) or a standard NGINX ingress controller.

###  Render templates locally (dry-run, no cluster connection needed)

Render the templates locally
```bash
helm template charts/nginx -f charts/nginx/values.yaml --namespace staging
```
### Prerequisits for a local run

To run it locally, have pre-installed 
- docker 
- minikube (or kind)
- kubectl (within 2 minor version deviation from the kubernetes version)
- helm

### Pack and install the chart
```bash
cd charts/nginx
helm dependency update
helm install my-nginx . -f values.yaml --namespace staging --create-namespace
# Check the helm release
helm list -n staging
# Check pods are running
kubectl get pods -n staging
# Check services
kubectl get svc -n staging
```
Check the running helm release
```bash
helm list -n staging
```
If the chart needs to get packed and distributed:
```bash
cd charts
helm package nginx
helm repo index . --url https://your-repo-url/charts
```

### Test the nginx server (minikube locally installed)
Port-forward to access the nginx service
```bash
kubectl port-forward -n staging svc/my-nginx 8080:80
```
Access via browser (http://localhost:8080) or curl
```bash
curl http://localhost:8080
```

### Uninstall the helm release
```bash
helm uninstall my-nginx -n staging
```
Make sure pods are gone (clean up)
```bash
kubectl get pods -n staging
```

### Further considerations
Set charts/nginx/values.yaml → ingress.hosts[0].host to a custom domain.
For AWS Load Balancer Controller, set ingress.className: alb and ensure the controller is installed.


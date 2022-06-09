vpc_container = "10.124.0.0/16"
public_cidrs = ["10.124.1.0/24","10.124.2.0/24"]
private_cidrs = ["10.124.3.0/24", "10.124.4.0/24","10.124.5.0/24", "10.124.6.0/24"]
region = "us-east-1"
machine_instances = ["ami-04505e74c0741db8d","terraform_key"]
machine_bastion = ["ami-0e1d30f2c40c4c701","terraform_key"]
deploy_zone = "prod"
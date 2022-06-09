variable "vpc_container" {
  type    = string
  default = "10.124.0.0/16"
}

variable "public_cidrs" {
type = list(string)
	default = ["10.124.1.0/24", "10.124.2.0/24"]
}

variable "private_cidrs" {
  type    = list(string)
  default = ["10.124.3.0/24", "10.124.4.0/24"]
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "machine_instances"{
  type = list(string)
  default = ["ami-04505e74c0741db8d","terraform_key"]

}

variable "machine_bastion"{
  type = list(string)
  default = ["ami-0e1d30f2c40c4c701","terraform_key"]

}

variable "deploy_zone"{
  type = string
  default = "prod"
}
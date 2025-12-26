variable "name" {
    description = "Name of the type of Vault deployment"
    type = string
    default = "community"
}

variable "vpc_region" {
    description = "The Region the VPC and resources will be deployed in"
    type = string
    default = "us-east-2"
}

variable "vpc_id" {
    description = "The ID of the VPC"
    type = string
    default = ""
}



variable "ssh_cidr" {
    description = "From what CIDR block would you like to allow SSH"
    type = string
    default = "0.0.0.0/0"
}



variable "instance_type" {
    description = "What instance type would you like to use"
    type = string
    default = "t3.small"
}


variable "vault_version" {
    description = "What version of Vault "
    type = string
    default = "1.18.2"
}

variable "cluster_name" {
    description = "What is the name of the cluster"
    type = string
    default = "vault-aws-lab"
}

variable "domain_name" {
    description = "What is the domain name"
    type = string
    default = "value"
  
}

variable "node_id" {
    description = "What is the ID of the node"
    type = list(string)
    default = [ "1", "2", "3" ]
  
}

variable "raft_retry_join_addresses" {
    description = "What are the retry join addresses"
    type = list(string)
    default = [ "https://10.0.1.10:8200", "https://10.0.2.10:8200", "https://10.0.3.10:8200" ]
  
}

variable "enable_tls" {
    description = "Should TLS be enabled"
    type = bool
    default = false
  
}

# Step 5 (TLS) - pass base64 strings if you want user_data to write them.
variable "tls_cert_b64" { 
    type = string 
    default = "" 
}

variable "tls_key_b64"  { 
    type = string
    default = "" 
}

variable "tls_ca_b64"   { 
    type = string
    default = "" 
}
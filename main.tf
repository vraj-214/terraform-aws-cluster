terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.27.0"
    }
  }
}

provider "aws" {
    region = var.vpc_region
}

data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "vault" {
    name = "${var.name}-vault-sg"
    vpc_id = aws_vpc.vault_vpc.id

    #Allow LB -> Vault 8200
    ingress {
        from_port = 8200
        to_port = 8200
        protocol = "tcp"
        security_groups = [aws_security_group.lb_sg.id]
    }

    #SSH from your IP
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [var.ssh_cidr]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_instance" "vault" {
    count = 3
    ami = data.aws_ami.ubuntu_2204.id
    instance_type = var.instance_type
    subnet_id = var.subnet_ids
    vpc_security_group_ids = [aws_security_group.vault.id]

    user_data = templatefile("$path.module}/user_data_vault.sh", {
        vault_version = var.vault_version,
        cluster_name = var.cluster_name,
        domain_name = var.domain_name,
        node_id = element(var.node_id, count.index),
        raft_retry_join_addresses = element(var.raft_retry_join_addresses, count.index),
        enable_tls = var.enable_tls,
        tls_certs_b64 = var.tls_certs_b64,
        tls_key_b64 = var.tls_key_b64,
        tls_ca_b64 = var.tls_ca_b64
    })

    tags = {
        Name ="${var.cluster_name}-vault-${count.index + 1}"
    }
}


  

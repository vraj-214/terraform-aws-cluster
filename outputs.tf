output "vault_instance_ids" {
  value = [for i in aws_instance.vault : i.id]
}

output "vault_instance_public_ips" {
  value = [for i in aws_instance.vault : i.public_ip]
}

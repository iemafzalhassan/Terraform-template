data "aws_region" "current" {}

output "configure_kubectl" {
  description = "Command to update kubeconfig for this cluster"
  value       = "aws eks --region ${data.aws_region.current.name} update-kubeconfig --name ${module.retail_app_eks.cluster_name}"
}

output "bastion_ssh_private_key" {
  description = "Private key for SSH access to the bastion host"
  value       = tls_private_key.bastion.private_key_pem
  sensitive   = true
}

output "bastion_ssh_command" {
  description = "SSH command to connect to the bastion host"
  value       = "ssh -i <(echo '${tls_private_key.bastion.private_key_pem}') ubuntu@${aws_instance.bastion.public_ip}"
  sensitive   = true
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

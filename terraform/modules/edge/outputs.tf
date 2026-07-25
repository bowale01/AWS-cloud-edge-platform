################################################################################
# Edge Module — Outputs
################################################################################

output "edge_vpc_id" {
  description = "ID of the edge VPC"
  value       = aws_vpc.edge.id
}

output "edge_subnet_id" {
  description = "ID of the edge subnet"
  value       = aws_subnet.edge.id
}

output "edge_instance_id" {
  description = "EC2 instance ID of the edge k3s node"
  value       = aws_instance.edge_node.id
}

output "edge_instance_public_ip" {
  description = "Public IP of the edge k3s node (reachable from platform VPC via peering)"
  value       = aws_instance.edge_node.public_ip
}

output "edge_instance_private_ip" {
  description = "Private IP of the edge k3s node (reachable from platform VPC via peering)"
  value       = aws_instance.edge_node.private_ip
}

output "vpc_peering_connection_id" {
  description = "VPC peering connection ID — passed to platform VPC module for route table entries"
  value       = aws_vpc_peering_connection.edge_to_platform.id
}

output "ssm_connect_command" {
  description = "Command to connect to edge node via SSM (no SSH keys needed)"
  value       = "aws ssm start-session --target ${aws_instance.edge_node.id}"
}

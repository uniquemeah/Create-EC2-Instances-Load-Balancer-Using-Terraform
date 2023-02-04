# Output
output "instance_ips" {
  value = aws_instance.ubuntu-server.*.private_ip 
}

output "alb_id" {
  value = aws_lb.production-ALB.dns_name
}
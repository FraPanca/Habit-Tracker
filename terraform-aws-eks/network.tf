data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Tag richiesti perché il cluster sappia dove piazzare un Load Balancer.
resource "aws_ec2_tag" "cluster_subnet_tag" {
  for_each    = toset(data.aws_subnets.default.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.project_name}-cluster"
  value       = "shared"
}

resource "aws_ec2_tag" "elb_subnet_tag" {
  for_each    = toset(data.aws_subnets.default.ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}
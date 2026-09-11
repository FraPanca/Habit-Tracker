resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group per la istanza EC2 di ${var.project_name}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP da chiunque"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH solo dal mio IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Tutto il traffico in uscita"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}
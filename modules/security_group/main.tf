resource "aws_security_group" "tf_sg" {
  name = ""
  description = var.desc
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.pjt_name}-sg"
  }
}

variable "region" {
  type        = string
  default     = ""
}

variable "vpc_id" {
  type = string
  default = ""
}

variable "igw_id" {
  type = string
  default = ""
}

variable "pjt_name" {
  type = string
  default = ""
}

variable "nacl_id" {
  type = string
  default = ""
}

variable "subnet_ids" {
  type = list(string)
  default = []
}

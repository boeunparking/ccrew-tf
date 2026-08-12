output "vpc_id" {
  value = module.vpc.vpc_id
}

output "igw_id" {
  value = module.vpc.igw_id
}

output "subnet_ids" {
  value = { for k, v in module.subnet : k => v.sn_id }
}

output "alb_sg_id" {
  value = module.alb_sg.sg_id
}

output "ecs_sg_id" {
  value = module.ecs_sg.sg_id
}

output "db_sg_id" {
  value = module.db_sg.sg_id
}

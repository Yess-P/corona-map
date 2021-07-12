variable aws_region_list {
  type        = list(string)
  default     = ["ap-northeast-2"]
  description = "region"
}

variable name {
  type        = string
  default     = "kube"
  description = "all_name"
}

variable amis {
  type        = string
  default     = "ami-07464b2b9929898f8"
  description = "which ami "
}


variable availability_zones {
  type        = list(string)
  default     = ["ap-northeast-2a"]
  description = "A comma-delimited list of availability zones for the VPC."
}

variable zones {
  type        = list(string)
  default     = ["A"]
  description = "choose zone"
}

variable public_subnet {
  type        = list(string)
  default     = ["192.168.1.0/24", "192.168.2.0/24"]
}

variable private_subnet {
  type        = list(string)
  default     = ["192.168.10.0/24", "192.168.11.0/24"]
}

variable all_subnet {
  type        = list(string)
  default     =  ["192.168.1.0/24", "192.168.2.0/24", "192.168.10.0/24", "192.168.11.0/24"]
}


variable Cluster_name {
  type        = string
  default     = "EKS-CLUSTER"
  description = "CLUSTER NAME"
}

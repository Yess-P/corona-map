variable eks_cluster_name {
  type        = string
  default     = "EKS-CLUSTER"
}

variable instance {
  type        = string
  default     = "t2.small"
  description = "choose your instance"
}

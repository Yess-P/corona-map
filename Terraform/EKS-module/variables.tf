variable Cluster_name {
  type        = string
  default     = "EKS-CLUSTER"
  description = "CLUSTER NAME"
}

variable map_accounts {
  type        = list(string)
  default     = ["997041077086"]
}

variable map_roles {
  type        = list(object({
    rolearn   = string
    username  = string
    groups     = list(string)
  }))

  default     = [
    {
      rolearn   = "arn:aws:iam::997041077086:role:role2"
      username  = "yess"
      groups    = ["system:master"]
    }
  ]

}

variable map_users {
  type        = list(object({
    userarn   = string
    username  = string
    groups     = list(string)
  }))

  default     = [
    {
      userarn   = "arn:aws:iam::997041077086:user/yess"
      username  = "yess"
      groups    = ["system:master"]
    }
  ]
}


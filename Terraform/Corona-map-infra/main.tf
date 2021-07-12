# VPC
module vpc {
  source                = "../modules/VPC"
  name                  = "Kube"
  availability_zones    = ["ap-northeast-2a","ap-northeast-2c"]
  zones                 = ["A","C"]
}

#Cluster
resource "aws_eks_cluster" "EKS-CLUSTER" {
  # CloudWatch Logs로 각 log들을 전송, 추가비용 발생
  # enable_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  name        = var.eks_cluster_name
  role_arn    = aws_iam_role.eks.arn

  version     = "1.20"
  vpc_config{
      endpoint_public_access  = true
      endpoint_private_access = true
      public_access_cidrs = [
        "0.0.0.0/0",
        ]
      subnet_ids  = module.vpc.all_subnet
    }

  depends_on = [
  aws_iam_role_policy_attachment.eks-AmazonEKSClusterPolicy,
  aws_iam_role_policy_attachment.eks-AmazonEKSVPCResourceController,
  aws_iam_role_policy_attachment.eks-AmazonEKSServicePolicy
  ]

}


resource "aws_iam_role" "eks" {
  name = var.eks_cluster_name

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
        "Effect": "Allow",
        "Principal": {
            "Service": "eks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
        }
    ]
}
  EOF
}

data "tls_certificate" "cert" {
  # cluster가 가지고 있는 oidc issuer
  url             = aws_eks_cluster.EKS-CLUSTER.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "openid"{
  client_id_list  = ["sts.amazonaws.com"]
  # tls 인증서가 가지고 있는 지문
  thumbprint_list = [data.tls_certificate.cert.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.EKS-CLUSTER.identity[0].oidc[0].issuer
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSClusterPolicy"{
    policy_arn      = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    role            = aws_iam_role.eks.name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSServicePolicy" {
  policy_arn        = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role              = aws_iam_role.eks.name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSVPCResourceController" {
  policy_arn        = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role              = aws_iam_role.eks.name
}

resource "aws_security_group" "eks_cluster" {
  name            = "${var.eks_cluster_name}/ControlPlaneSecurityGroup"
  description     = "Communication between the control plane and worker nodegroups"
  vpc_id          = module.vpc.vpc_id

  egress{
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
      Name        = "${var.eks_cluster_name}/ControlPlaneSecurityGroup"
  }
}

resource "aws_security_group_rule" "cluster_inbound" {
  description                 = "Allow unmanaged nodes to communicate with control plane (all ports)"
  from_port                   = 0
  protocol                    = "-1"
  security_group_id           = aws_eks_cluster.EKS-CLUSTER.vpc_config[0].cluster_security_group_id
  source_security_group_id    = aws_security_group.eks_nodes.id
  to_port                     = 0
  type                        = "ingress"
}

resource "aws_security_group_rule" "cluster_private_access" {
  description                 = "Allow private K8S API ingress from custom source."
  from_port                   = 443
  protocol                    = "tcp"
  security_group_id           = aws_eks_cluster.EKS-CLUSTER.vpc_config[0].cluster_security_group_id
  source_security_group_id    = aws_security_group.EKS-Bastion-SG.id
  to_port                     = 443
  type                        = "ingress"
  
}



######### node_group #########
resource "aws_launch_template" "lt-ng"{
  name                  = "lt-ng"
  instance_type         = var.instance
}

resource "aws_eks_node_group" "private"{
  cluster_name          = aws_eks_cluster.EKS-CLUSTER.name
  node_group_name       = "private"
  node_role_arn         = aws_iam_role.node-group.arn
  subnet_ids            = module.vpc.private_subnet

  labels                = {
    "type" = "private"
  }

  instance_types        = []

  launch_template {
    name                = aws_launch_template.lt-ng.name
    version             = "1"
  }

  scaling_config {
    desired_size        = 2
    max_size            = 3
    min_size            = 1
  }

  depends_on            = [
    aws_iam_role_policy_attachment.node-group-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node-group-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node-group-AmazonEC2ContainerRegistryReadOnly,
    aws_launch_template.lt-ng
  ]
}

# resource "aws_eks_node_group" "public"{
#   cluster_name          = aws_eks_cluster.EKS-CLUSTER.name
#   node_group_name       = "public"
#   node_role_arn        = aws_iam_role.node-group.arn
#   subnet_ids            = module.vpc.public_subnet

#   labels                = {
#     "type" = "public"
#   }

#   instance_types        = []

#   launch_template {
#     name                = aws_launch_template.lt-ng.name
#     version             = "1"
#   }

#   scaling_config {
#     desired_size        = 1
#     max_size            = 3
#     min_size            = 1
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.node-group-AmazonEKSWorkerNodePolicy,
#     aws_iam_role_policy_attachment.node-group-AmazonEKS_CNI_Policy,
#     aws_iam_role_policy_attachment.node-group-AmazonEC2ContainerRegistryReadOnly,
#     aws_launch_template.lt-ng
#   ]

# }


resource "aws_iam_role" "node-group"{
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "node-group-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node-group.name
}

resource "aws_iam_role_policy_attachment" "node-group-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node-group.name
}

resource "aws_iam_role_policy_attachment" "node-group-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node-group.name
}

resource "aws_iam_role_policy" "node-group-ClusterAutoscalerPolicy" {
  name = "eks-cluster-auto-scaler"
  role = aws_iam_role.node-group.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeLaunchConfigurations",
            "autoscaling:DescribeTags",
            "autoscaling:SetDesiredCapacity",
            "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "node-group-AmazonEKS_EBS_CSI_DriverPolicy" {
  name = "AmazonEKS_EBS_CSI_Driver_Policy"
  role = aws_iam_role.node-group.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
            "ec2:AttachVolume",
            "ec2:CreateSnapshot",
            "ec2:CreateTags",
            "ec2:CreateVolume",
            "ec2:DeleteSnapshot",
            "ec2:DeleteTags",
            "ec2:DeleteVolume",
            "ec2:DescribeAvailabilityZones",
            "ec2:DescribeInstances",
            "ec2:DescribeSnapshots",
            "ec2:DescribeTags",
            "ec2:DescribeVolumes",
            "ec2:DescribeVolumesModifications",
            "ec2:DetachVolume",
            "ec2:ModifyVolume"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ebs-csi-controller" {
  name = "AmazonEKS_EBS_CSI_DriverRole"

  assume_role_policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Federated": aws_iam_openid_connect_provider.openid.arn
                },
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Condition": {
                    "StringEquals": {
                        "${replace(aws_iam_openid_connect_provider.openid.url, "https://", "")}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
                    }
                }
            }
        ]
    })
}

resource "aws_security_group" "eks_nodes" {
  name        = "${var.eks_cluster_name}/ClusterSharedNodeSecurityGroup"
  description = "Communication between all nodes in the cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_eks_cluster.EKS-CLUSTER.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.eks_cluster_name}/ClusterSharedNodeSecurityGroup"
  }
}

# bastion
resource "aws_security_group" "EKS-Bastion-SG"{
    name = "EKS-Bastion-SG"
    vpc_id =  module.vpc.vpc_id

    ingress {
        from_port   = 22
        protocol    = "tcp"
        to_port     = 22
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        protocol    = "-1"
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = { "Name" = "EKS-Bastion-SG" }
}


resource "aws_instance" "EKS-Bastion"{
    ami                         = "ami-0f2c95e9fe3f8f80e"
    instance_type               = "t2.micro"
    subnet_id                   = element(module.vpc.public_subnet,0)
    key_name                    = "terraform-key"
    associate_public_ip_address = true

    vpc_security_group_ids      = [aws_security_group.EKS-Bastion-SG.id]

    depends_on                  = [
        aws_security_group.EKS-Bastion-SG,
        # aws_eks_cluster.EKS-CLUSTER                        
        ]

    connection {
        type                    = "ssh"
        host                    = self.public_ip
        user                    = "ec2-user"
        # 현재 테라폼 코드가 존재하는 위치
        private_key             = file("${path.module}/terraform-key.pem")
        timeout                 = "2m"
        agent                   = false
      }

    provisioner "remote-exec" {
      inline = [
        "curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip\n",
        "unzip awscliv2.zip",
        "sudo ./aws/install\n",

        "curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.12/2020-11-02/bin/linux/amd64/kubectl",
        "chmod +x ./kubectl",
        "mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin",

        "curl -o aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.19.6/2021-01-05/bin/linux/amd64/aws-iam-authenticator",
        "chmod +x ./aws-iam-authenticator",
        "mkdir -p $HOME/bin && cp ./aws-iam-authenticator $HOME/bin/aws-iam-authenticator && export PATH=$PATH:$HOME/bin",
        "echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc",

        "curl --silent --location https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz | tar xz -C /tmp",
        "sudo mv /tmp/eksctl /usr/local/bin",

        "curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh",
        "chmod 700 get_helm.sh",
        "./get_helm.sh",

        "sudo yum install git -y",
        "helm repo add eks https://aws.github.io/eks-charts"
      ]

    }

    tags = {
        "Name" = "EKS-Bastion"
        }
}


resource "aws_security_group" "EKS-Jenkins-SG"{
    name    = "EKS-Jenkins-SG"
    vpc_id  =  module.vpc.vpc_id

    egress {
        from_port   = 0
        protocol    = "-1"
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
    }

    depends_on                  = [aws_security_group.EKS-Bastion-SG]

    tags = {
        "Name" = "EKS-Jenkins-SG"
    }
}

resource "aws_security_group_rule" "EKS-Jenkins-ssh-inbound" {
  from_port                   = 22
  protocol                    = "-1"
  security_group_id           = aws_security_group.EKS-Jenkins-SG.id
  source_security_group_id    = aws_security_group.EKS-Bastion-SG.id
  to_port                     = 22
  type                        = "ingress"
}

resource "aws_security_group_rule" "EKS-Jenkins-web" {
  from_port                   = 8080
  protocol                    = "-1"
  security_group_id           = aws_security_group.EKS-Jenkins-SG.id
  to_port                     = 8080
  type                        = "ingress"
  cidr_blocks                 = ["0.0.0.0/0"]
}

resource "aws_instance" "EKS-Jenkins"{
    ami                         = "ami-0f2c95e9fe3f8f80e"
    instance_type               = "t2.small"
    subnet_id                   = element(module.vpc.private_subnet,0)
    key_name                    = "terraform-key"

    vpc_security_group_ids      = [aws_security_group.EKS-Jenkins-SG.id]

    depends_on                  = [aws_security_group.EKS-Jenkins-SG]

    tags = {
        "Name" = "EKS-Jenkins"
        }
}


##########Jenkins Slave###########
resource "aws_security_group" "EKS-Jenkins-Slave-SG"{
    name    = "EKS-Jenkins-Slave-SG"
    vpc_id  =  module.vpc.vpc_id

    egress {
        from_port   = 0
        protocol    = "-1"
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
    }

    depends_on                  = [aws_security_group.EKS-Jenkins-Slave-SG]

    tags = {
        "Name" = "EKS-Jenkins-Slave-SG"
    }
}

resource "aws_security_group_rule" "EKS-Jenkins-slave-ssh-inbound-Jenkins" {
  from_port                   = 22
  protocol                    = "-1"
  security_group_id           = aws_security_group.EKS-Jenkins-Slave-SG.id
  source_security_group_id    = aws_security_group.EKS-Jenkins-SG.id
  to_port                     = 22
  type                        = "ingress"
}

resource "aws_security_group_rule" "EKS-Jenkins-slave-ssh-inbound-Bastion" {
  from_port                   = 22
  protocol                    = "-1"
  security_group_id           = aws_security_group.EKS-Jenkins-Slave-SG.id
  source_security_group_id    = aws_security_group.EKS-Bastion-SG.id
  to_port                     = 22
  type                        = "ingress"
}

resource "aws_instance" "EKS-Jenkins-Slave"{
    ami                         = "ami-0f2c95e9fe3f8f80e"
    instance_type               = "t2.small"
    subnet_id                   = element(module.vpc.private_subnet,0)
    key_name                    = "terraform-key"

    vpc_security_group_ids      = [aws_security_group.EKS-Jenkins-Slave-SG.id]

    depends_on                  = [aws_security_group.EKS-Jenkins-Slave-SG]

    tags = {
        "Name" = "EKS-Jenkins-Slave"
        }
}

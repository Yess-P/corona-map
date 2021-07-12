data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

module vpc {
  source                = "../VPC"
  name                  = "kube"
  availability_zones    = ["ap-northeast-2a","ap-northeast-2c"]
  zones = ["A","C"]
}


resource "aws_security_group" "worker_group_mgmt_sg" {
  vpc_id  = module.vpc.vpc_id


  ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [
            "0.0.0.0/0",
        ]
  }
  tags = {
        Name = "Worker_group_mgmt_sg"
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  vpc_id  = module.vpc.vpc_id

  ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [
            "0.0.0.0/0",
            "172.16.0.0/12",
            "192.168.0.0/16"

        ]
  }
  tags = {
        Name = "all_worker_mgmt_sg"
  }
}


provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.9"
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "16.0.0"

  cluster_name    = "${var.Cluster_name}"
  cluster_version = "1.17"
  
  subnets         = module.vpc.private_subnet

  vpc_id          = module.vpc.vpc_id

  # private endpoint가 kubernetes에 자동으로 connect & join 되게 하는 설정
  cluster_endpoint_private_access = true

  # gp3를 사용하지 못하는 지역에서는 gp2로 수정 해야한다.
  workers_group_defaults = {
  	root_volume_type = "gp2"
  }

  worker_groups = [
    {
      name          = "worker-group-1"
      instance_type = "t2.micro"
      # additoial_userdata = "echo foo bar"
      # 원하는 크기의 auto scaling group 
      asg_desired_capacity = 1
      asg_max_size  = 3
      
      # auto scaling group의 securuty group 설정
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_sg.id]

    },
    {
      name          = "worker-group-2"
      instance_type = "t2.micro"
      
      asg_desired_capacity  = 1
      asg_max_size          = 3
      
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_sg.id]
      map_role      = var.map_roles
      map_user      = var.map_users
      map_accounts  = var.map_accounts
      
    }
  ]

  # worker_groups_launch_template = [aws_launch_configuration.kube.id]

  tags = {
        Name = "EKS-CLUSTER"
  }
}

resource "aws_security_group" "bastion-sg"{
    name = "bastion"
    vpc_id =  module.vpc.vpc_id

    ingress {
        from_port = 22
        protocol = "tcp"
        to_port = 22
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        protocol = "-1"
        to_port = 0
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        "Name" = "bastion-sg"
    }
}


resource "aws_instance" "bastion"{
    ami                         = "ami-0f2c95e9fe3f8f80e"
    instance_type               = "t2.micro"
    subnet_id                   = element(module.vpc.public_subnet,0)
    key_name                    = "terraform-key"
    associate_public_ip_address = true

    vpc_security_group_ids      = [aws_security_group.bastion-sg.id]

    depends_on                  = [
        aws_security_group.bastion-sg,
        # aws_eks_cluster.mycluster1                        
        ]

    connection {
        type                    = "ssh"
        host                    = self.public_ip
        user                    = "ec2-user"
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
        "Name" = "EKS-bastion"
        }
}

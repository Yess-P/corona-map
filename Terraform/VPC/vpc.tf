# VPC
resource "aws_vpc" "main" {
    cidr_block            = "192.168.0.0/16"
    instance_tenancy      = "default"
    enable_dns_hostnames  = true
    enable_dns_support    = true


    tags = {
        Name = "${var.name}-vpc"
        "kubernetes.io/cluster/${var.Cluster_name}" = "shared"
    }  

}

# public Subnet
resource "aws_subnet" "public" {
    count             = length(var.availability_zones)
    vpc_id            = aws_vpc.main.id

    # cidr_block = "192.168.${count.index+1}.0/24"
    cidr_block        = element(var.public_subnet, count.index)
    availability_zone = element(var.availability_zones, count.index)
    map_public_ip_on_launch = true

    tags = {
        Name = "KUBE-PUB-${var.zones[count.index]}",
        "kubernetes.io/cluster/${var.Cluster_name}" = "shared",
        "kubernetes.io/role/alb-ingress"             = "1",
        "kubernetes.io/role/elb"                     = "1"
        
    }
}

# IGW
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-IGW"
  }
}

# Route Table
resource "aws_route_table" "public" {
    count = length(var.availability_zones)
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${var.name}-PUB-Route-${var.zones[count.index]}"
    }

}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = element(aws_route_table.public.*.id, count.index)
}

resource "aws_route" "public" {
  count                         = length(var.availability_zones)
  route_table_id                = element(aws_route_table.public.*.id, count.index)
  destination_cidr_block        = "0.0.0.0/0"
  gateway_id                    = aws_internet_gateway.IGW.id
}

# Private Subnet
resource "aws_subnet" "private" {
    count             = length(var.availability_zones)
    vpc_id            = aws_vpc.main.id

    # cidr_block = "192.168.${count.index+10}.0/24"
    cidr_block        = element(var.private_subnet, count.index)

    availability_zone = element(var.availability_zones, count.index)

    map_public_ip_on_launch = false

    tags = {
        Name = "${var.name}-PRI-${var.zones[count.index]}"
        Network = "Private"
        "kubernetes.io/cluster/${var.Cluster_name}" = "shared"
        "kubernetes.io/role/internal-elb"            = "1"
      
    }
}

resource "aws_route_table" "private" {
    count = length(var.availability_zones)
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${var.name}-PRI-Route-${var.zones[count.index]}"
        Network = "Private"
    }

}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_route" "private" {
  count                   = length(var.availability_zones)
  route_table_id          = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block  = "0.0.0.0/0"
  nat_gateway_id          = aws_nat_gateway.NGW.id

  # Multi-NGW
  # nat_gateway_id          = element(aws_nat_gateway.NGW.*.id, count.index)
}

## NAT Gateway 
resource "aws_nat_gateway" "NGW" {
  # Count means how many you want to create the same resource
  # This will be generated with array format
  # For example, if the number of availability zone is three, then nat[0], nat[1], nat[2] will be created.
  # If you want to create each resource with independent name, then you have to copy the same code and modify some code
  # count = length(var.availability_zones)

  # element is used for select the resource from the array 
  # Usage = element (array, index) => equals array[index]
  allocation_id = aws_eip.EIP.id
  # allocation_id = element(aws_eip.EIP.*.id, count.index)
  

  #Subnet Setting
  # nat[0] will be attached to subnet[0]. Same to all index.
  subnet_id = aws_subnet.public[0].id

  # Multi-NGW
  # subnet_id = element(aws_subnet.public.*.id, count.index)

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.name}-NAT"
    
    # Multi-NGW
    # Name = "${var.name}-NAT-${var.zones[count.index]}"
  }

}

# Elastic IP for NAT Gateway 
resource "aws_eip" "EIP" {
  # Count value should be same with that of aws_nat_gateway because all nat will get elastic ip
  # count = length(var.availability_zones)
  vpc   = true

  lifecycle {
    create_before_destroy = true
  }
}

provider "aws" {
    region = var.aws_region_list[0]
    shared_credentials_file = "~/.aws/credentials"
}

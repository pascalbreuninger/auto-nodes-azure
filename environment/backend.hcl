terraform {
  backend "s3" {
    name    = "${var.vcluster.name}-tfstate"
    key     = "environment/terraform.tfstate"
    region  = var.vcluster.requirements["region"]
    encrypt = true
  }
}

terraform {
  backend "s3" {
    name    = "${var.vcluster.name}-tfstate"
    key     = "node/terraform.tfstate"
    region  = var.vcluster.requirements["region"]
    encrypt = true
  }
}

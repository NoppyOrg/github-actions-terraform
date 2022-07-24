terraform {
  backend "s3" {
    bucket         = "githubactions-terraformbackend-1v11g13v4ungw"
    key            = "user-b/terraform.tfstate"
    dynamodb_table = "terraform-lock-state-table"
    region         = "ap-northeast-1"
  }
}

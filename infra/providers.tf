terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.6"
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

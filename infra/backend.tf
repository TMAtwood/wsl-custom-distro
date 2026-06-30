# Azure Blob backend — partial config. Supply values at init time via -backend-config flags
# or a .tfbackend file (never commit real values):
#
#   tofu init \
#     -backend-config="resource_group_name=<rg>" \
#     -backend-config="storage_account_name=<sa>" \
#     -backend-config="container_name=tfstate" \
#     -backend-config="key=wsl-custom-distro.tfstate"
#
# To use a local backend during development (before Azure storage is wired), comment out
# the azurerm block below and uncomment this:
#
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

terraform {
  backend "azurerm" {}
}

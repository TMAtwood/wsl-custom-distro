# github_actions_runner_group requires GitHub Team or Enterprise.
# The TMAtwood org is currently on the Free plan, so every resource and data source in this
# file is guarded with count = var.enable_runner_group ? 1 : 0  (or the equivalent length).
#
# `tofu plan` with the default (enable_runner_group = false) produces zero resources and
# exits cleanly. Flip enable_runner_group = true in terraform.tfvars once the org is upgraded.

data "github_repository" "selected" {
  count = var.enable_runner_group ? length(var.selected_repository_names) : 0
  name  = var.selected_repository_names[count.index]
}

resource "github_actions_runner_group" "fcg_local" {
  count                   = var.enable_runner_group ? 1 : 0
  name                    = var.runner_group_name
  visibility              = "selected"
  selected_repository_ids = data.github_repository.selected[*].repo_id
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the repositories."
  type        = string
  default     = "TMAtwood"
}

variable "github_token" {
  description = "Fine-grained PAT with org self-hosted-runners read/write. Supplied at apply time; never stored in VCS."
  type        = string
  sensitive   = true
}

variable "runner_group_name" {
  description = "Name of the GitHub Actions runner group."
  type        = string
  default     = "fcg-local"
}

variable "selected_repository_names" {
  description = "Repository names (within github_owner) whose workflows may use the runner group."
  type        = list(string)
  default     = ["wsl-custom-distro"]
}

variable "enable_runner_group" {
  description = <<-EOT
    Set to true to create the GitHub Actions runner group.
    Custom runner groups require GitHub Team or Enterprise.
    The TMAtwood org is currently on the Free plan, so this defaults to false.
    Flip to true once the org is upgraded.
  EOT
  type        = bool
  default     = false
}

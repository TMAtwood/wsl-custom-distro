output "runner_group_id" {
  description = "Numeric ID of the runner group — used in supervisor.sh generate-jitconfig calls. Null when enable_runner_group = false."
  value       = one(github_actions_runner_group.fcg_local[*].id)
}

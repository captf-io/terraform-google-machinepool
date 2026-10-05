# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Contract outputs of the machinepool role, in contract order:
# https://captf.io/docs/module-author/contract/v1alpha1/machinepool.html#outputs
# and "health" in https://captf.io/docs/module-author/contract/v1alpha1/common.html

output "provider_id" {
  description = "The managed instance group's ID, projects/<p>/regions/<r>/instanceGroupManagers/<name> (machinepool.md \"provider_id\")."
  value       = one(google_compute_region_instance_group_manager.pool_instance_group_manager[*].id)
}

output "provider_id_list" {
  description = "gce://<project>/<zone>/<instance> of every member that is not going away, whatever its state (machinepool.md \"provider_id_list\")."
  value       = sort(keys(local.live_members_by_provider_id))
}

output "replicas" {
  description = "The group's observed desired capacity: the autoscaler's while it scales (machinepool.md \"replicas\")."
  # A number even once the group is gone: health reports the loss.
  value = coalesce(local.desired_replicas, 0)
}

output "instances" {
  description = "Per-member detail: provider ID, instance name, zone and health state (machinepool.md \"instances\")."
  value = [
    for id, m in local.live_members_by_provider_id : {
      provider_id    = id
      instance_id    = m.name
      addresses      = []
      failure_domain = m.zone
      state          = m.health.state
    }
  ]
}

output "health" {
  description = "Health from the members and the desired capacity (README \"Health\"; common.md \"health\")."
  value       = local.health_reading
}

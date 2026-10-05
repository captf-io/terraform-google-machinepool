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

# Non-contract outputs: ids of what the module created, for operators and for
# the tests' stability checks. The controller never reads them. Alphabetical.

output "autoscaler_id" {
  description = "ID of the autoscaler; null without autoscaling."
  value       = try(google_compute_region_autoscaler.pool_autoscaler[0].id, null)
}

output "dropped_node_labels" {
  description = "Keys of node_labels the kubelet may not set on itself (kubernetes.io and k8s.io namespaces under NodeRestriction), which the pool does not register."
  value       = local.dropped_node_labels
}

output "instance_group_manager_id" {
  description = "ID of the managed instance group; changes only when the group is replaced."
  value       = one(google_compute_region_instance_group_manager.pool_instance_group_manager[*].instance_group_manager_id)
}

# A single resource: after an out-of-band delete a refresh reads it as
# unknown, and try() does not turn that into null; the output is stored null.
output "instance_template_id" {
  description = "ID of the current instance template; changes when the pool rolls."
  value       = try(google_compute_region_instance_template.pool_instance_template.id, null)
}

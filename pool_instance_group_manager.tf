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

# The native scaling group: a regional managed instance group over the
# pool's zones (DESIGN.md decision 5). The role's primary resource: it carries
# the cross-variable checks.
resource "google_compute_region_instance_group_manager" "pool_instance_group_manager" {
  # count = 1, not a single resource: after an out-of-band delete a refresh
  # reads an empty tuple rather than an unknown, so health reports the loss.
  count = 1

  base_instance_name               = local.base_instance_name
  description                      = local.description
  distribution_policy_target_shape = "EVEN"
  distribution_policy_zones        = local.zones
  name                             = local.pool_name
  project                          = local.project
  region                           = local.region
  # Optional and computed: null leaves the autoscaler's count alone, so an
  # apply never resets it; without an autoscaler, replicas is authoritative
  # (machinepool.md "autoscaling"; README "Exceptions").
  target_size        = local.autoscaler_enabled ? null : var.replicas
  wait_for_instances = false

  # The bootstrap payload rotates every few minutes. Here a rotation changes
  # instance metadata only: a REFRESH that never restarts or replaces an
  # instance, and new instances boot with the current token.
  all_instances_config {
    labels   = local.tags
    metadata = local.user_data_metadata
  }

  # PROACTIVE with REFRESH as the least action: a metadata change refreshes
  # in place; a new image (a kubernetes_version change) needs REPLACE, one
  # surge instance per zone at a time and none taken away first.
  update_policy {
    instance_redistribution_type   = "PROACTIVE"
    max_surge_fixed                = length(local.zones)
    max_unavailable_fixed          = 0
    minimal_action                 = "REFRESH"
    most_disruptive_allowed_action = "REPLACE"
    replacement_method             = "SUBSTITUTE"
    type                           = "PROACTIVE"
  }

  version {
    instance_template = google_compute_region_instance_template.pool_instance_template.self_link
    name              = "primary"
  }

  lifecycle {
    precondition {
      condition     = local.cluster_exports != null
      error_message = "The TerraformCluster is externally managed (captf_cluster_outputs is {}): set spec.variables.external_cluster_exports on the TerraformMachinePool to exports of schema captf.io/gcp-cluster/v1."
    }
    precondition {
      condition     = !local.explicit_zones || length(setsubtract(var.failure_domains, local.cluster_zones)) == 0
      error_message = "failure_domains must be failure domains of the cluster (${join(", ", local.cluster_zones)}); these are not: ${join(", ", setsubtract(var.failure_domains, local.cluster_zones))}."
    }
    precondition {
      condition     = length(local.zones) > 0
      error_message = "The pool has no zones: the cluster exports no failure domains and the MachinePool sets none."
    }
    precondition {
      condition     = (local.autoscaler_enabled ? var.autoscaling.max : var.replicas) <= local.max_members
      error_message = "A pool holds at most ${local.max_members} instances: the member listing is one page of ${local.max_members}. Lower the MachinePool's replicas or its cluster-api-autoscaler-node-group-max-size annotation, or split the pool."
    }
    precondition {
      condition     = !(var.bootstrap_format == "ignition" && local.render_node_labels)
      error_message = "node_labels need a cloud-config bootstrap payload: Ignition has no boothook to register them. Remove the MachinePool template labels or use cloud-config."
    }
    precondition {
      condition     = !(var.bootstrap_format == "ignition" && local.bootstrap_gzipped)
      error_message = "A gzipped Ignition payload is not supported: Ignition reads GCE user-data uncompressed. Turn off gzipUserData in the bootstrap config."
    }
    precondition {
      condition     = length(local.user_data) <= local.user_data_max_bytes
      error_message = "The pool's user-data is ${nonsensitive(length(local.user_data))} bytes, over the ${local.user_data_max_bytes}-byte metadata value limit: gzip the bootstrap payload or shrink it."
    }
  }
}

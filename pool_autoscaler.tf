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

# The GCE autoscaler, while the MachinePool's autoscaler annotations enable
# autoscaling: it owns the group's desired count between min and max
# (machinepool.md "autoscaling"); none for a maximum of 0. CPU-based.
resource "google_compute_region_autoscaler" "pool_autoscaler" {
  count = local.autoscaler_enabled ? 1 : 0

  description = local.description
  name        = local.pool_name
  project     = local.project
  region      = local.region
  target      = google_compute_region_instance_group_manager.pool_instance_group_manager[0].id

  autoscaling_policy {
    # The initialization period: CPU readings of a booting node are ignored.
    cooldown_period = var.autoscaling_initialization_seconds
    max_replicas    = var.autoscaling.max
    min_replicas    = var.autoscaling.min
    mode            = "ON"

    cpu_utilization {
      target = var.autoscaling_target_cpu_percent / 100
    }
  }
}

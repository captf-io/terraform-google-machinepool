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

# The zones the group spreads over: the MachinePool's failure domains, else
# the cluster's zones as pinned at the first apply (pool_default_zones.tf).
# Changing them replaces the group: distribution_policy_zones is ForceNew.
locals {
  explicit_zones = length(var.failure_domains) > 0
  zones          = local.explicit_zones ? sort(var.failure_domains) : terraform_data.pool_default_zones.output

  # The autoscaler exists only with a positive maximum: min = max = 0 means
  # an empty group, which a target size of 0 says without one.
  autoscaler_enabled = var.autoscaling.enabled && var.autoscaling.max > 0

  # listInstances answers in one page of at most 500 instances, and the
  # provider does not page (data_pool_members.tf).
  max_members = 500
}

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

# Names of the group, its instances and its templates, derived from the
# MachinePool's key with a hash that keeps truncated names unique
# (CONVENTIONS.md section 6).
locals {
  pool_key  = "${var.captf_object.namespace}/${var.machinepool_name}"
  pool_hash = substr(sha256(local.pool_key), 0, 8)
  # Compute Engine names allow no dots
  # (https://cloud.google.com/compute/docs/naming-resources).
  pool_slug = replace(lower("captf-${var.captf_object.namespace}-${var.machinepool_name}"), "/[^a-z0-9-]/", "-")

  # Group and autoscaler: at most 63 characters, 9 of them "-" and the hash.
  pool_name = "${trimsuffix(substr(local.pool_slug, 0, 63 - 9), "-")}-${local.pool_hash}"
  # Instances are <base>-<4 characters>, and their names are the Node names,
  # so the base is at most 58 characters.
  base_instance_name = "${trimsuffix(substr(local.pool_slug, 0, 58 - 9), "-")}-${local.pool_hash}"
  # The provider appends a 26-character suffix to a name_prefix of at most 37.
  template_name_prefix = "${trimsuffix(substr(local.pool_slug, 0, 36 - 9), "-")}-${local.pool_hash}-"

  # Descriptions name the objects, never captf_tags: description is ForceNew
  # on the group, and captf.io/template can change.
  description = "CAPTF machine pool ${local.pool_key} of cluster ${var.captf_cluster.namespace}/${var.captf_cluster.name}"
}

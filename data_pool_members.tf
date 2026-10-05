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

# The group's members, with every instance state (the data source lists
# instanceState ALL in one request of at most 500 instances; README
# "Limitations"). Re-read on every refresh: the membership the controller syncs.
data "google_compute_region_instance_group" "pool_members" {
  # None once the group is gone, so a refresh does not fail reading it.
  count = length(google_compute_region_instance_group_manager.pool_instance_group_manager)

  self_link = google_compute_region_instance_group_manager.pool_instance_group_manager[count.index].instance_group
}

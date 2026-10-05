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

# Pool membership and health from the group's member listing and its target
# size, re-read on every refresh (CONVENTIONS.md section 10; machinepool.md
# "Per-instance state").
locals {
  # Compute Engine instance status -> contract health, as for a machine.
  health_by_state = {
    RUNNING        = { state = "running", reason = null }
    PENDING        = { state = "pending", reason = "InstancePending" }
    PROVISIONING   = { state = "pending", reason = "InstanceProvisioning" }
    STAGING        = { state = "pending", reason = "InstanceStaging" }
    REPAIRING      = { state = "degraded", reason = "InstanceRepairing" }
    PENDING_STOP   = { state = "stopped", reason = "InstancePendingStop" }
    STOPPING       = { state = "stopped", reason = "InstanceStopping" }
    STOPPED        = { state = "stopped", reason = "InstanceStopped" }
    SUSPENDING     = { state = "stopped", reason = "InstanceSuspending" }
    SUSPENDED      = { state = "stopped", reason = "InstanceSuspended" }
    TERMINATED     = { state = "stopped", reason = "InstanceTerminated" }
    DEPROVISIONING = { state = "terminated", reason = "InstanceNotFound" }
  }
  health_unknown = { state = "unknown", reason = "UnknownState" }

  # Every member, whatever its status (the data source lists instanceState
  # ALL), as gce://<project>/<zone>/<name>, what cloud-provider-gcp writes to
  # Node.spec.providerID.
  members = [
    for m in flatten(data.google_compute_region_instance_group.pool_members[*].instances) : {
      name        = regex("/instances/([^/]+)$", m.instance)[0]
      zone        = regex("/zones/([^/]+)/", m.instance)[0]
      provider_id = "gce://${regex("/projects/([^/]+)/", m.instance)[0]}/${regex("/zones/([^/]+)/", m.instance)[0]}/${regex("/instances/([^/]+)$", m.instance)[0]}"
      status      = upper(coalesce(m.status, "UNKNOWN"))
      health      = lookup(local.health_by_state, upper(coalesce(m.status, "UNKNOWN")), local.health_unknown)
    } if can(regex("/projects/[^/]+/zones/[^/]+/instances/[^/]+$", m.instance))
  ]
  # A member that is going away leaves provider_id_list; every other one
  # stays, whatever its state, or CAPI deletes its Node (machinepool.md
  # "provider_id_list").
  live_members = [for m in local.members : m if m.health.state != "terminated"]
  # Keyed and so sorted by provider ID, for stable outputs.
  live_members_by_provider_id = { for m in local.live_members : m.provider_id => m }

  # The group's desired capacity, as observed: the autoscaler's when it
  # scales. Null once a refresh no longer finds the group.
  desired_replicas = one(google_compute_region_instance_group_manager.pool_instance_group_manager[*].target_size)

  # A degraded, stopped or unknown member makes the group that state, worst
  # first; a starting member does not make it pending (CONVENTIONS.md
  # section 10; machinepool.md "Deriving group health").
  health_order  = ["degraded", "stopped", "unknown"]
  member_states = distinct([for m in local.live_members : m.health.state])
  worst_state   = try([for s in local.health_order : s if contains(local.member_states, s)][0], "running")
  # Machine-readable reasons naming the affected, then the starting, members.
  not_running = concat(
    [for m in local.live_members : "${m.health.reason}:${m.name}" if contains(local.health_order, m.health.state)],
    [for m in local.live_members : "${m.health.reason}:${m.name}" if m.health.state == "pending"],
  )

  health_reading = (
    local.desired_replicas == null ? {
      state   = "terminated"
      healthy = false
      message = "Instance group ${local.pool_name} not found."
      reasons = ["InstanceGroupNotFound"]
    } :
    # An autoscaled group is created empty and grows to its minimum: until a
    # member exists its desired capacity is that minimum, not zero.
    local.desired_replicas == 0 && !(local.autoscaler_enabled && var.autoscaling.min > 0) ? {
      state   = "running"
      healthy = true
      message = "Instance group ${local.pool_name} is scaled to zero."
      reasons = []
    } :
    length(local.live_members) == 0 ? {
      state   = "pending"
      healthy = false
      message = "Instance group ${local.pool_name} has no members yet; ${local.desired_replicas} desired."
      reasons = ["NoMembers"]
    } :
    {
      state   = local.worst_state
      healthy = length(local.not_running) == 0 && length(local.live_members) == local.desired_replicas
      message = "Instance group ${local.pool_name}: ${length(local.live_members)} of ${local.desired_replicas} members, ${length(local.live_members) - length(local.not_running)} running."
      reasons = concat(
        local.not_running,
        length(local.live_members) == local.desired_replicas ? [] : ["ScalingInProgress"],
      )
    }
  )
}

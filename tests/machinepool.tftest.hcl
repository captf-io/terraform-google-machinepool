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

# Unit tests of the machinepool role with a mocked Google provider: nothing
# reaches GCP. Run from the role directory with `terraform test` or
# `tofu test`, or `make unit-test`. Run names follow CONVENTIONS.md
# section 14.

mock_provider "google" {
  mock_resource "google_compute_region_instance_group_manager" {
    defaults = {
      instance_group = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/instanceGroups/captf-team-a-demo-workers-5c3b1a7e"
    }
  }

  mock_data "google_compute_region_instance_group" {
    defaults = {
      instances = [
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/captf-team-a-demo-workers-5c3b1a7e-k2lp", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instances/captf-team-a-demo-workers-5c3b1a7e-9xq1", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instances/captf-team-a-demo-workers-5c3b1a7e-z0de", status = "RUNNING", named_ports = [] },
      ]
    }
  }
}

variables {
  captf_contract = "v1alpha1"
  captf_cluster  = { name = "demo", namespace = "team-a" }
  captf_object   = { kind = "TerraformMachinePool", name = "demo-workers", namespace = "team-a" }
  captf_tags = {
    "captf.io/cluster"    = "demo"
    "captf.io/namespace"  = "team-a"
    "captf.io/kind"       = "TerraformMachinePool"
    "captf.io/name"       = "demo-workers"
    "captf.io/managed-by" = "captf"
    "captf.io/template"   = ""
  }
  captf_cluster_outputs = {
    schema      = "captf.io/gcp-cluster/v1"
    project     = "captf-test"
    region      = "us-central1"
    network     = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
    subnetwork  = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
    name_prefix = "captf-team-a-demo-1d4e2f6a"
    failure_domains = {
      "us-central1-a" = { zone = "us-central1-a" }
      "us-central1-b" = { zone = "us-central1-b" }
      "us-central1-c" = { zone = "us-central1-c" }
      "us-central1-f" = { zone = "us-central1-f" }
    }
    node_network_tag = "captf-team-a-demo-1d4e2f6a-node"
    control_plane = {
      service_account = "captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com"
      network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-control-plane"]
    }
    worker = {
      service_account = "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com"
      network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"]
    }
    api = {
      host         = "10.0.0.10"
      port         = 6443
      backend_port = 6443
      instance_groups = {
        "us-central1-a" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        "us-central1-b" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        "us-central1-c" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        "us-central1-f" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-f/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
      }
    }
  }
  machinepool_name = "demo-workers"
  replicas         = 3
  # base64 of "## template: jinja\n#cloud-config\nruncmd: [kubeadm join]\n"
  bootstrap_data          = "IyMgdGVtcGxhdGU6IGppbmphCiNjbG91ZC1jb25maWcKcnVuY21kOiBba3ViZWFkbSBqb2luXQo="
  bootstrap_format        = "cloud-config"
  failure_domains         = []
  cluster_failure_domains = ["us-central1-a", "us-central1-b", "us-central1-c"]
  kubernetes_version      = "v1.33.4"
  node_labels             = {}
  autoscaling             = { enabled = false, min = 0, max = 0 }

  image = "projects/captf-images/global/images/capi-ubuntu-2404-{slug}"
}

run "happy_path" {
  assert {
    condition     = output.provider_id == google_compute_region_instance_group_manager.pool_instance_group_manager[0].id
    error_message = "provider_id is the managed instance group's ID."
  }
  assert {
    condition = output.provider_id_list == tolist([
      "gce://captf-test/us-central1-a/captf-team-a-demo-workers-5c3b1a7e-9xq1",
      "gce://captf-test/us-central1-b/captf-team-a-demo-workers-5c3b1a7e-k2lp",
      "gce://captf-test/us-central1-c/captf-team-a-demo-workers-5c3b1a7e-z0de",
    ])
    error_message = "provider_id_list holds every member as gce://<project>/<zone>/<name>, sorted."
  }
  assert {
    condition     = output.replicas == 3
    error_message = "replicas is the group's target size."
  }
  assert {
    condition     = length(output.instances) == 3 && output.instances[0].provider_id == output.provider_id_list[0] && output.instances[0].instance_id == "captf-team-a-demo-workers-5c3b1a7e-9xq1" && output.instances[0].failure_domain == "us-central1-a" && output.instances[0].state == "running"
    error_message = "instances describe every member, in provider ID order."
  }
  assert {
    condition     = output.health.state == "running" && output.health.healthy && length(output.health.reasons) == 0
    error_message = "A group at its desired size with every member RUNNING is running and healthy."
  }
  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].name == "captf-team-a-demo-workers-${substr(sha256("team-a/demo-workers"), 0, 8)}"
    error_message = "The group is named after the MachinePool."
  }
  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].distribution_policy_zones == toset(["us-central1-a", "us-central1-b", "us-central1-c"])
    error_message = "Without failure_domains the group spreads over the cluster's failure domains."
  }
  assert {
    condition = alltrue([
      google_compute_region_instance_group_manager.pool_instance_group_manager[0].update_policy[0].type == "PROACTIVE",
      google_compute_region_instance_group_manager.pool_instance_group_manager[0].update_policy[0].minimal_action == "REFRESH",
      google_compute_region_instance_group_manager.pool_instance_group_manager[0].update_policy[0].most_disruptive_allowed_action == "REPLACE",
      google_compute_region_instance_group_manager.pool_instance_group_manager[0].update_policy[0].max_surge_fixed == 3,
      google_compute_region_instance_group_manager.pool_instance_group_manager[0].update_policy[0].max_unavailable_fixed == 0,
    ])
    error_message = "Updates are proactive: refresh in place, replace with one surge instance per zone."
  }
  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].version[0].instance_template == google_compute_region_instance_template.pool_instance_template.self_link
    error_message = "The group runs the current instance template."
  }
  assert {
    condition     = google_compute_region_instance_template.pool_instance_template.disk[0].source_image == "projects/captf-images/global/images/capi-ubuntu-2404-v1-33-4"
    error_message = "{slug} must become v1-33-4."
  }
  assert {
    condition     = google_compute_region_instance_template.pool_instance_template.service_account[0].email == "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com" && google_compute_region_instance_template.pool_instance_template.tags == toset(["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"])
    error_message = "Pool instances are workers: the worker service account and tags."
  }
  assert {
    condition = alltrue([
      google_compute_region_instance_template.pool_instance_template.metadata["block-project-ssh-keys"] == "TRUE",
      google_compute_region_instance_template.pool_instance_template.metadata["enable-oslogin"] == "TRUE",
      google_compute_region_instance_template.pool_instance_template.metadata["serial-port-enable"] == "FALSE",
      !contains(keys(google_compute_region_instance_template.pool_instance_template.metadata), "user-data"),
    ])
    error_message = "The template holds the secure defaults and never the bootstrap payload."
  }
  assert {
    condition     = length(google_compute_region_instance_template.pool_instance_template.network_interface[0].access_config) == 0 && google_compute_region_instance_template.pool_instance_template.shielded_instance_config[0].enable_secure_boot
    error_message = "No external IP; Shielded VM on."
  }
  assert {
    condition     = nonsensitive(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"]) == var.bootstrap_data && google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data-encoding"] == "base64"
    error_message = "Without node labels the payload goes as it is, base64, in the all-instances config."
  }
}

run "reapply_is_stable" {
  variables {
    previous_template_id = run.happy_path.instance_template_id
    previous_group_id    = run.happy_path.instance_group_manager_id
  }

  assert {
    condition     = output.instance_template_id == var.previous_template_id && output.instance_group_manager_id == var.previous_group_id
    error_message = "A second apply must keep the template and the group."
  }
}

run "bootstrap_rotation_in_place" {
  variables {
    # A rotated token: base64 of "## template: jinja\n#cloud-config\nruncmd: [kubeadm join 2]\n"
    bootstrap_data       = "IyMgdGVtcGxhdGU6IGppbmphCiNjbG91ZC1jb25maWcKcnVuY21kOiBba3ViZWFkbSBqb2luIDJdCg=="
    previous_template_id = run.reapply_is_stable.instance_template_id
    previous_group_id    = run.reapply_is_stable.instance_group_manager_id
  }

  assert {
    condition     = output.instance_template_id == var.previous_template_id && output.instance_group_manager_id == var.previous_group_id
    error_message = "A bootstrap rotation keeps the instance template and the group: nothing is replaced."
  }
  assert {
    condition     = nonsensitive(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"]) == "IyMgdGVtcGxhdGU6IGppbmphCiNjbG91ZC1jb25maWcKcnVuY21kOiBba3ViZWFkbSBqb2luIDJdCg=="
    error_message = "The rotated payload reaches the all-instances config, for new instances."
  }
}

# Not asserted by template id: Terraform's mock never plans a ForceNew
# replacement, so a new image is the evidence of a new template (every
# template argument is ForceNew).
run "kubernetes_version_rolls" {
  variables {
    kubernetes_version = "v1.34.1"
    previous_group_id  = run.bootstrap_rotation_in_place.instance_group_manager_id
  }

  assert {
    condition     = output.instance_group_manager_id == var.previous_group_id
    error_message = "The group itself is kept: it rolls its instances."
  }
  assert {
    condition     = google_compute_region_instance_template.pool_instance_template.disk[0].source_image == "projects/captf-images/global/images/capi-ubuntu-2404-v1-34-1"
    error_message = "The new template boots the new version's image: every template argument is ForceNew, so this is a new template."
  }
  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].version[0].instance_template == google_compute_region_instance_template.pool_instance_template.self_link
    error_message = "The group targets the new template, so PROACTIVE replaces its instances."
  }
}

run "tags_on_taggable_resources" {
  variables {
    additional_tags      = { team = "platform" }
    previous_template_id = run.kubernetes_version_rolls.instance_template_id
  }

  assert {
    condition     = output.instance_template_id == var.previous_template_id
    error_message = "A label change keeps the instance template, so it never rolls the pool."
  }

  assert {
    condition = google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].labels == tomap({
      "captf-io_cluster"    = "demo"
      "captf-io_namespace"  = "team-a"
      "captf-io_kind"       = "terraformmachinepool"
      "captf-io_name"       = "demo-workers"
      "captf-io_managed-by" = "captf"
      "captf-io_template"   = ""
      "team"                = "platform"
    })
    error_message = "The all-instances config labels every instance with the mapped captf_tags and additional_tags, in place."
  }
  assert {
    condition = google_compute_region_instance_template.pool_instance_template.labels == tomap({
      "captf-io_cluster"    = "demo"
      "captf-io_namespace"  = "team-a"
      "captf-io_kind"       = "terraformmachinepool"
      "captf-io_name"       = "demo-workers"
      "captf-io_managed-by" = "captf"
      "captf-io_template"   = ""
    })
    error_message = "The template keeps the labels it was created with: its labels are ForceNew, so a label change must not roll the pool."
  }
  assert {
    condition     = google_compute_region_instance_template.pool_instance_template.disk[0].labels == google_compute_region_instance_template.pool_instance_template.labels
    error_message = "The boot disks carry the template's labels."
  }
}

run "autoscaling_disabled" {
  variables {
    replicas = 2
  }

  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = [
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instances/captf-team-a-demo-workers-5c3b1a7e-9xq1", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/captf-team-a-demo-workers-5c3b1a7e-k2lp", status = "RUNNING", named_ports = [] },
      ]
    }
  }

  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].target_size == 2 && output.replicas == 2
    error_message = "Without autoscaling, replicas sets the group's target size."
  }
  assert {
    condition     = length(google_compute_region_autoscaler.pool_autoscaler) == 0 && output.autoscaler_id == null
    error_message = "Without autoscaling there is no autoscaler."
  }
  assert {
    condition     = output.health.healthy
    error_message = "Two running members of two desired is healthy."
  }
}

run "autoscaling_enabled" {
  variables {
    replicas    = 5
    autoscaling = { enabled = true, min = 1, max = 10 }
  }

  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = [
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instances/captf-team-a-demo-workers-5c3b1a7e-9xq1", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/captf-team-a-demo-workers-5c3b1a7e-k2lp", status = "RUNNING", named_ports = [] },
      ]
    }
  }

  assert {
    condition     = google_compute_region_autoscaler.pool_autoscaler[0].autoscaling_policy[0].min_replicas == 1 && google_compute_region_autoscaler.pool_autoscaler[0].autoscaling_policy[0].max_replicas == 10
    error_message = "The autoscaler takes min and max from the MachinePool's annotations."
  }
  assert {
    condition     = google_compute_region_autoscaler.pool_autoscaler[0].target == google_compute_region_instance_group_manager.pool_instance_group_manager[0].id && google_compute_region_autoscaler.pool_autoscaler[0].autoscaling_policy[0].cpu_utilization[0].target == 0.6
    error_message = "The autoscaler scales the group on CPU."
  }
  assert {
    # The target size is left to the autoscaler: replicas (5) is not applied.
    # (Terraform's mock keeps the previous run's 2; OpenTofu's reports 0.)
    condition     = output.replicas != 5 && google_compute_region_instance_group_manager.pool_instance_group_manager[0].target_size != 5
    error_message = "With autoscaling the apply must leave the target size to the autoscaler, not set it to replicas."
  }
}

run "autoscaling_first_apply_pending" {
  variables {
    autoscaling = { enabled = true, min = 2, max = 5 }
  }

  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = []
    }
  }

  assert {
    condition     = output.health.state == "pending" && !output.health.healthy
    error_message = "An autoscaled group with a minimum above zero and no members yet is pending, never scaled to zero."
  }
}

run "zero_replicas_healthy" {
  variables {
    replicas = 0
  }

  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = []
    }
  }

  assert {
    condition     = output.replicas == 0 && length(output.provider_id_list) == 0 && length(output.instances) == 0
    error_message = "A group scaled to zero has no members."
  }
  assert {
    condition     = output.health.state == "running" && output.health.healthy
    error_message = "A group scaled to zero is running and healthy."
  }
}

run "health_pending_without_members" {
  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = []
    }
  }

  assert {
    condition     = output.health.state == "pending" && !output.health.healthy && output.health.reasons == tolist(["NoMembers"])
    error_message = "A group with no members yet is pending."
  }
}

run "health_scaling" {
  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = [
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instances/captf-team-a-demo-workers-5c3b1a7e-9xq1", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/captf-team-a-demo-workers-5c3b1a7e-k2lp", status = "RUNNING", named_ports = [] },
      ]
    }
  }

  assert {
    condition     = output.health.state == "running" && !output.health.healthy && output.health.reasons == tolist(["ScalingInProgress"])
    error_message = "Every member running but fewer than desired is running, not yet healthy."
  }
}

run "health_starting_member" {
  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = [
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instances/captf-team-a-demo-workers-5c3b1a7e-9xq1", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/captf-team-a-demo-workers-5c3b1a7e-k2lp", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instances/captf-team-a-demo-workers-5c3b1a7e-z0de", status = "STAGING", named_ports = [] },
      ]
    }
  }

  assert {
    condition     = output.health.state == "running" && !output.health.healthy && output.health.reasons == tolist(["InstanceStaging:captf-team-a-demo-workers-5c3b1a7e-z0de"])
    error_message = "A starting member leaves the pool running, not yet healthy, and is named; it never makes the pool pending."
  }
}

run "health_worst_member" {
  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = [
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instances/captf-team-a-demo-workers-5c3b1a7e-9xq1", status = "STAGING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/captf-team-a-demo-workers-5c3b1a7e-k2lp", status = "TERMINATED", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instances/captf-team-a-demo-workers-5c3b1a7e-z0de", status = "REPAIRING", named_ports = [] },
      ]
    }
  }

  assert {
    condition     = output.health.state == "degraded" && !output.health.healthy
    error_message = "The group's state is its worst member's: degraded before stopped before pending."
  }
  assert {
    condition     = output.health.reasons == tolist(["InstanceTerminated:captf-team-a-demo-workers-5c3b1a7e-k2lp", "InstanceRepairing:captf-team-a-demo-workers-5c3b1a7e-z0de", "InstanceStaging:captf-team-a-demo-workers-5c3b1a7e-9xq1"])
    error_message = "reasons name the affected members, then the starting ones."
  }
  assert {
    condition     = [for i in output.instances : i.state] == ["pending", "stopped", "degraded"]
    error_message = "instances carry each member's state."
  }
}

run "health_stopped" {
  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = [
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instances/captf-team-a-demo-workers-5c3b1a7e-9xq1", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/captf-team-a-demo-workers-5c3b1a7e-k2lp", status = "SUSPENDED", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instances/captf-team-a-demo-workers-5c3b1a7e-z0de", status = "SOMETHING_NEW", named_ports = [] },
      ]
    }
  }

  assert {
    condition     = output.health.state == "stopped" && [for i in output.instances : i.state] == ["running", "stopped", "unknown"]
    error_message = "stopped is worse than unknown; an unmapped status is unknown."
  }
}

run "membership_excludes_terminated" {
  override_data {
    target = data.google_compute_region_instance_group.pool_members
    values = {
      instances = [
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instances/captf-team-a-demo-workers-5c3b1a7e-9xq1", status = "RUNNING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/captf-team-a-demo-workers-5c3b1a7e-k2lp", status = "DEPROVISIONING", named_ports = [] },
        { instance = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instances/captf-team-a-demo-workers-5c3b1a7e-z0de", status = "TERMINATED", named_ports = [] },
      ]
    }
  }

  assert {
    condition = output.provider_id_list == tolist([
      "gce://captf-test/us-central1-a/captf-team-a-demo-workers-5c3b1a7e-9xq1",
      "gce://captf-test/us-central1-c/captf-team-a-demo-workers-5c3b1a7e-z0de",
    ])
    error_message = "A member going away leaves provider_id_list; a stopped (TERMINATED) one stays, or CAPI would delete its Node."
  }
  assert {
    condition     = length(output.instances) == 2
    error_message = "instances lists the same members."
  }
}

run "node_labels_rendered" {
  variables {
    node_labels = {
      "node-role.kubernetes.io/worker" = ""
      "node.kubernetes.io/pool"        = "workers"
      "topology.kubernetes.io/zone"    = "us-central1-a"
      "team.example.com/owner"         = "platform"
      "foo.k8s.io/bar"                 = "x"
      "tier"                           = "batch"
    }
    previous_template_id = run.membership_excludes_terminated.instance_template_id
  }

  assert {
    condition     = output.instance_template_id == var.previous_template_id
    error_message = "A node_labels change updates the all-instances config only: the template is kept."
  }
  assert {
    condition     = startswith(nonsensitive(base64decode(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"])), "Content-Type: multipart/mixed; boundary=\"captf-")
    error_message = "With node labels the user-data is a MIME multipart message."
  }
  assert {
    condition     = strcontains(nonsensitive(base64decode(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"])), "captf_node_labels='node.kubernetes.io/pool=workers,team.example.com/owner=platform,tier=batch,topology.kubernetes.io/zone=us-central1-a'")
    error_message = "The boothook passes the allowed labels, sorted, to the kubelet."
  }
  assert {
    condition     = strcontains(nonsensitive(base64decode(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"])), "printf 'node-label+:\\n'") && strcontains(nonsensitive(base64decode(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"])), "# captf-node-labels begin")
    error_message = "The boothook carries the shared fragment: a marked kubelet block and RKE2's appending node-label+ list."
  }
  assert {
    condition     = !strcontains(nonsensitive(base64decode(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"])), "node-role.kubernetes.io") && !strcontains(nonsensitive(base64decode(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"])), "foo.k8s.io")
    error_message = "Labels the kubelet may not set (kubernetes.io and k8s.io namespaces) are dropped."
  }
  assert {
    condition     = output.dropped_node_labels == tolist(["foo.k8s.io/bar", "node-role.kubernetes.io/worker"])
    error_message = "dropped_node_labels lists the labels left out."
  }
  assert {
    condition     = strcontains(nonsensitive(base64decode(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"])), "Content-Type: text/plain; charset=\"utf-8\"\nMIME-Version: 1.0\nContent-Transfer-Encoding: base64\nContent-Disposition: attachment; filename=\"bootstrap\"\n\n${var.bootstrap_data}\n")
    error_message = "The payload follows unchanged, as a base64 part."
  }
  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data-encoding"] == "base64"
    error_message = "The multipart message goes as base64."
  }
}

run "node_labels_gzipped_payload" {
  variables {
    bootstrap_data = "H4sIAAAAAAAAA1NWyEgtSk1RBABx0wMrCgAAAA=="
    node_labels    = { tier = "batch" }
  }

  assert {
    condition     = strcontains(nonsensitive(base64decode(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"])), "Content-Type: application/x-gzip\n")
    error_message = "A gzipped payload is an application/x-gzip part, which cloud-init decompresses."
  }
}

run "node_labels_unsupported_format" {
  command = plan

  variables {
    bootstrap_format = "ignition"
    # base64 of {"ignition":{"version":"3.4.0"}}
    bootstrap_data = "eyJpZ25pdGlvbiI6eyJ2ZXJzaW9uIjoiMy40LjAifX0="
    node_labels    = { tier = "batch" }
  }

  expect_failures = [google_compute_region_instance_group_manager.pool_instance_group_manager]
}

run "bootstrap_ignition" {
  variables {
    bootstrap_format = "ignition"
    bootstrap_data   = "eyJpZ25pdGlvbiI6eyJ2ZXJzaW9uIjoiMy40LjAifX0="
    # Only labels the kubelet may not set: nothing to render.
    node_labels = { "node-role.kubernetes.io/worker" = "" }
  }

  assert {
    condition     = nonsensitive(google_compute_region_instance_group_manager.pool_instance_group_manager[0].all_instances_config[0].metadata["user-data"]) == "{\"ignition\":{\"version\":\"3.4.0\"}}"
    error_message = "Ignition reads user-data raw, so it is decoded."
  }
}

run "rejects_gzipped_ignition" {
  command = plan

  variables {
    bootstrap_format = "ignition"
    bootstrap_data   = "H4sIAAAAAAAAA1NWyEgtSk1RBABx0wMrCgAAAA=="
  }

  expect_failures = [google_compute_region_instance_group_manager.pool_instance_group_manager]
}

run "bootstrap_too_large" {
  command = plan

  variables {
    # 262148 characters: 4 over the limit.
    bootstrap_data = format("%0262148d", 0)
  }

  expect_failures = [google_compute_region_instance_group_manager.pool_instance_group_manager]
}

run "failure_domains_default_to_cluster" {
  variables {
    failure_domains = []
  }

  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].distribution_policy_zones == toset(["us-central1-a", "us-central1-b", "us-central1-c"])
    error_message = "Without failure_domains the group spreads over cluster_failure_domains."
  }
  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].update_policy[0].max_surge_fixed == 3
    error_message = "One surge instance per zone."
  }
}

# A cluster zone change must not replace a default-zoned group: the pool's
# zones are pinned at its first apply (pool_default_zones.tf).
run "cluster_zone_change_keeps_group" {
  variables {
    failure_domains         = []
    cluster_failure_domains = ["us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"]
    previous_group_id       = run.failure_domains_default_to_cluster.instance_group_manager_id
  }

  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].distribution_policy_zones == toset(["us-central1-a", "us-central1-b", "us-central1-c"])
    error_message = "The group keeps the zones it was created with."
  }
  assert {
    condition     = output.instance_group_manager_id == var.previous_group_id
    error_message = "The group is not replaced."
  }
}

run "failure_domains_requested" {
  variables {
    failure_domains = ["us-central1-f"]
  }

  assert {
    condition     = google_compute_region_instance_group_manager.pool_instance_group_manager[0].distribution_policy_zones == toset(["us-central1-f"])
    error_message = "failure_domains pins the group's zones."
  }
}

run "rejects_failure_domain_outside_cluster" {
  command = plan

  variables {
    failure_domains = ["us-east1-b"]
  }

  expect_failures = [google_compute_region_instance_group_manager.pool_instance_group_manager]
}

run "spot_pool" {
  command = plan

  variables {
    spot = true
  }

  assert {
    condition     = google_compute_region_instance_template.pool_instance_template.scheduling[0].provisioning_model == "SPOT" && google_compute_region_instance_template.pool_instance_template.scheduling[0].instance_termination_action == "STOP"
    error_message = "spot makes the pool's instances Spot VMs that stop when preempted."
  }
}

run "boot_disk_kms_key_id" {
  command = plan

  variables {
    boot_disk_kms_key_id = "projects/captf-test/locations/us-central1/keyRings/nodes/cryptoKeys/disks"
  }

  assert {
    condition     = google_compute_region_instance_template.pool_instance_template.disk[0].disk_encryption_key[0].kms_key_self_link == "projects/captf-test/locations/us-central1/keyRings/nodes/cryptoKeys/disks"
    error_message = "boot_disk_kms_key_id encrypts the boot disks."
  }
}

run "externally_managed_without_override" {
  command = plan

  variables {
    captf_cluster_outputs = {}
  }

  expect_failures = [google_compute_region_instance_group_manager.pool_instance_group_manager]
}

run "externally_managed_with_override" {
  command = plan

  variables {
    captf_cluster_outputs = {}
    external_cluster_exports = {
      schema      = "captf.io/gcp-cluster/v1"
      project     = "captf-test"
      region      = "us-central1"
      network     = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
      subnetwork  = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
      name_prefix = "captf-team-a-demo-1d4e2f6a"
      failure_domains = {
        "us-central1-a" = { zone = "us-central1-a" }
        "us-central1-b" = { zone = "us-central1-b" }
        "us-central1-c" = { zone = "us-central1-c" }
        "us-central1-f" = { zone = "us-central1-f" }
      }
      node_network_tag = "captf-team-a-demo-1d4e2f6a-node"
      control_plane = {
        service_account = "captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-control-plane"]
      }
      worker = {
        service_account = "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"]
      }
      api = {
        host         = "10.0.0.10"
        port         = 6443
        backend_port = 6443
        instance_groups = {
          "us-central1-a" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-b" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-c" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-f" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-f/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        }
      }
    }
  }

  assert {
    condition     = google_compute_region_instance_template.pool_instance_template.network_interface[0].subnetwork == "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
    error_message = "external_cluster_exports stands in for the cluster's exports."
  }
}

run "wrong_exports_schema" {
  command = plan

  variables {
    captf_cluster_outputs = { schema = "captf.io/gcp-cluster/v2" }
  }

  expect_failures = [var.captf_cluster_outputs]
}

run "rejects_image_without_placeholder" {
  command = plan

  variables {
    image = "projects/captf-images/global/images/family/capi-ubuntu-2404"
  }

  expect_failures = [google_compute_region_instance_template.pool_instance_template]
}

run "rejects_image_placeholder_without_version" {
  command = plan

  variables {
    kubernetes_version = null
  }

  expect_failures = [google_compute_region_instance_template.pool_instance_template]
}

run "kubernetes_version_suffix_rolls" {
  command = plan

  variables {
    image              = "projects/captf-images/global/images/rke2-ubuntu-2404-{fullslug}"
    kubernetes_version = "v1.31.4+rke2r2"
  }

  assert {
    condition     = google_compute_region_instance_template.pool_instance_template.disk[0].source_image == "projects/captf-images/global/images/rke2-ubuntu-2404-v1-31-4-rke2r2"
    error_message = "{fullslug} keeps the build suffix, so a suffix-only upgrade changes the image and rolls the pool."
  }
}

run "rejects_suffixed_version_without_fullslug" {
  command = plan

  variables {
    kubernetes_version = "v1.31.4+rke2r2"
  }

  expect_failures = [google_compute_region_instance_template.pool_instance_template]
}

run "autoscaling_max_zero" {
  command = plan

  variables {
    autoscaling = { enabled = true, min = 0, max = 0 }
    replicas    = 0
  }

  assert {
    condition     = length(google_compute_region_autoscaler.pool_autoscaler) == 0 && google_compute_region_instance_group_manager.pool_instance_group_manager[0].target_size == 0
    error_message = "A maximum of 0 is an empty group without an autoscaler."
  }
}

run "rejects_replicas_over_member_limit" {
  command = plan

  variables {
    replicas = 501
  }

  expect_failures = [google_compute_region_instance_group_manager.pool_instance_group_manager]
}

run "rejects_autoscaling_max_over_member_limit" {
  command = plan

  variables {
    autoscaling = { enabled = true, min = 1, max = 600 }
  }

  expect_failures = [google_compute_region_instance_group_manager.pool_instance_group_manager]
}

# Validations, one run each.

run "invalid_captf_contract" {
  command = plan
  variables {
    captf_contract = "v2"
  }
  expect_failures = [var.captf_contract]
}

run "invalid_replicas" {
  command = plan
  variables {
    replicas = 1.5
  }
  expect_failures = [var.replicas]
}

run "invalid_bootstrap_format" {
  command = plan
  variables {
    bootstrap_format = "shell"
  }
  expect_failures = [var.bootstrap_format]
}

run "invalid_node_labels" {
  command = plan
  variables {
    node_labels = { "tier" = "batch; reboot" }
  }
  expect_failures = [var.node_labels]
}

run "invalid_additional_tags_count" {
  command = plan
  variables {
    additional_tags = { for i in range(59) : "k${i}" => "v" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_syntax" {
  command = plan
  variables {
    additional_tags = { "1team" = "x" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_reserved" {
  command = plan
  variables {
    additional_tags = { "captf-io_name" = "x" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_autoscaling_target_cpu_percent" {
  command = plan
  variables {
    autoscaling_target_cpu_percent = 150
  }
  expect_failures = [var.autoscaling_target_cpu_percent]
}

run "invalid_autoscaling_initialization_seconds" {
  command = plan
  variables {
    autoscaling_initialization_seconds = -1
  }
  expect_failures = [var.autoscaling_initialization_seconds]
}

run "invalid_disk_kms_key" {
  command = plan
  variables {
    boot_disk_kms_key_id = "my-key"
  }
  expect_failures = [var.boot_disk_kms_key_id]
}

run "invalid_disk_size_gib" {
  command = plan
  variables {
    boot_disk_size_gib = 9
  }
  expect_failures = [var.boot_disk_size_gib]
}

run "invalid_disk_type" {
  command = plan
  variables {
    boot_disk_type = "standard"
  }
  expect_failures = [var.boot_disk_type]
}

run "invalid_external_cluster_exports" {
  command = plan
  variables {
    external_cluster_exports = { project = "captf-test" }
  }
  expect_failures = [var.external_cluster_exports]
}

run "invalid_image_missing" {
  command = plan
  variables {
    image = null
  }
  expect_failures = [var.image]
}

run "invalid_image_whitespace" {
  command = plan
  variables {
    image = "my image"
  }
  expect_failures = [var.image]
}

run "invalid_machine_type" {
  command = plan
  variables {
    machine_type = "big"
  }
  expect_failures = [var.machine_type]
}

run "invalid_additional_network_tags" {
  command = plan
  variables {
    additional_network_tags = ["-bad"]
  }
  expect_failures = [var.additional_network_tags]
}

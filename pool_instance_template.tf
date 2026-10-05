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

# Everything a pool instance is made of except the bootstrap payload, which
# rotates and lives in the group's all-instances config (DESIGN.md decision 5).
# Templates are immutable: a change creates a new one first, then the group rolls.
resource "google_compute_region_instance_template" "pool_instance_template" {
  can_ip_forward = var.can_ip_forward
  description    = local.description
  labels         = local.tags
  machine_type   = var.machine_type
  # OS Login instead of metadata SSH keys, project-wide keys blocked, no
  # interactive serial console (CONVENTIONS.md section 8).
  metadata = {
    "block-project-ssh-keys" = "TRUE"
    "enable-oslogin"         = "TRUE"
    "serial-port-enable"     = "FALSE"
  }
  name_prefix = local.template_name_prefix
  project     = local.project
  region      = local.region
  tags        = local.network_tags

  disk {
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_size_gib
    disk_type    = var.boot_disk_type
    labels       = local.tags
    source_image = local.image

    dynamic "disk_encryption_key" {
      for_each = var.boot_disk_kms_key_id == null ? [] : [var.boot_disk_kms_key_id]

      content {
        kms_key_self_link = disk_encryption_key.value
      }
    }
  }

  # No access_config: no external IP. Nodes reach the internet through the
  # Cloud NAT of the network you bring.
  network_interface {
    stack_type = "IPV4_ONLY"
    subnetwork = local.subnetwork
  }

  # Spot VMs stop when preempted; the group restarts them when it can.
  scheduling {
    automatic_restart           = !var.spot
    instance_termination_action = var.spot ? "STOP" : null
    on_host_maintenance         = var.spot ? "TERMINATE" : "MIGRATE"
    preemptible                 = var.spot
    provisioning_model          = var.spot ? "SPOT" : "STANDARD"
  }

  # cloud-platform scope: access is decided by the account's IAM roles
  # (https://cloud.google.com/compute/docs/access/service-accounts#scopes_best_practice).
  service_account {
    email  = local.service_account
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = var.secure_boot
    enable_vtpm                 = true
  }

  lifecycle {
    # The group still references the old template until it switches to the
    # new one, so the old one can only go afterwards.
    create_before_destroy = true
    # Labels are ForceNew on a template (its effective_labels and disk
    # labels), so a captf_tags change would roll the pool. Instances get
    # current labels in place from all_instances_config instead.
    ignore_changes = [labels, disk[0].labels]

    precondition {
      condition     = local.kubernetes_semver == null || local.image_has_placeholder
      error_message = "image ${coalesce(var.image, "-")} has no {version}, {semver}, {slug} or {fullslug} placeholder: a kubernetes_version change must roll the pool (machinepool.md \"Lifecycle\"), so the image must name the version."
    }
    precondition {
      condition     = !local.kubernetes_has_suffix || local.image_has_fullslug
      error_message = "kubernetes_version ${coalesce(var.kubernetes_version, "-")} has a build suffix (+...), which only {fullslug} carries: name the image with {fullslug} so a suffix-only upgrade rolls the pool too."
    }
    precondition {
      condition     = !local.image_has_placeholder || local.kubernetes_semver != null
      error_message = "image ${coalesce(var.image, "-")} holds a {version}, {semver}, {slug} or {fullslug} placeholder but the MachinePool has no spec.template.spec.version to fill it."
    }
  }
}

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

# The pool's user-data: node_labels as a boothook, then the opaque bootstrap
# payload, in one MIME message (CONVENTIONS.md section 13; machinepool.md
# "node_labels"). bootstrap_data is base64; gzip's base64 starts with "H4sI".
locals {
  # Whether the payload is compressed is not secret.
  bootstrap_gzipped = nonsensitive(startswith(var.bootstrap_data, "H4sI"))

  # The kubelet refuses to start with a kubernetes.io or k8s.io label it may
  # not set itself, and NodeRestriction rejects it, so those are dropped
  # unless allowed (k8s.io/kubernetes pkg/kubelet/apis/well_known_labels.go
  # and plugin/pkg/admission/noderestriction).
  kubelet_allowed_labels = [
    "beta.kubernetes.io/arch",
    "beta.kubernetes.io/instance-type",
    "beta.kubernetes.io/os",
    "failure-domain.beta.kubernetes.io/region",
    "failure-domain.beta.kubernetes.io/zone",
    "kubernetes.io/arch",
    "kubernetes.io/hostname",
    "kubernetes.io/os",
    "node.kubernetes.io/instance-type",
    "topology.kubernetes.io/region",
    "topology.kubernetes.io/zone",
  ]
  kubelet_allowed_namespaces = ["kubelet.kubernetes.io", "node.kubernetes.io"]
  node_label_namespaces      = { for k in keys(var.node_labels) : k => strcontains(k, "/") ? lower(split("/", k)[0]) : "" }
  node_labels = {
    for k, v in var.node_labels : k => v
    if !anytrue([for ns in ["kubernetes.io", "k8s.io"] : local.node_label_namespaces[k] == ns || endswith(local.node_label_namespaces[k], ".${ns}")]) ||
    contains(local.kubelet_allowed_labels, k) ||
    anytrue([for ns in local.kubelet_allowed_namespaces : local.node_label_namespaces[k] == ns || endswith(local.node_label_namespaces[k], ".${ns}")])
  }
  # Ignition has no boothook: it fails the group's precondition when there
  # are labels to register.
  render_node_labels = length(local.node_labels) > 0

  dropped_node_labels = sort(setsubtract(keys(var.node_labels), keys(local.node_labels)))

  node_labels_boothook = templatefile("${path.module}/templates/node_labels_boothook.tftpl", {
    node_labels = join(",", [for k in sort(keys(local.node_labels)) : "${k}=${local.node_labels[k]}"])
  })

  # The payload stays opaque: its base64 becomes a base64 MIME part, which
  # cloud-init decodes and, as application/x-gzip, decompresses. text/plain
  # lets cloud-init detect the type from the content (#cloud-config or
  # "## template: jinja").
  user_data_mime = templatefile("${path.module}/templates/user_data.tftpl", {
    boundary             = "captf-${local.pool_hash}"
    boothook             = local.node_labels_boothook
    payload_content_type = local.bootstrap_gzipped ? "application/x-gzip" : "text/plain; charset=\"utf-8\""
    payload_base64       = join("\n", regexall(".{1,76}", var.bootstrap_data))
  })

  # cloud-config goes as base64 with user-data-encoding=base64, which
  # cloud-init's GCE datasource decodes (cloudinit/sources/DataSourceGCE.py).
  # Ignition reads user-data raw: decoded, and only when not gzipped.
  user_data = (
    var.bootstrap_format == "cloud-config" ? (local.render_node_labels ? base64encode(local.user_data_mime) : var.bootstrap_data) :
    # Safe outside a cloud-config check (CONVENTIONS.md section 13): an
    # Ignition config is JSON, so UTF-8, once gzip is ruled out.
    var.bootstrap_format == "ignition" && !local.bootstrap_gzipped ? base64decode(var.bootstrap_data) :
    ""
  )
  user_data_metadata = var.bootstrap_format == "cloud-config" ? tomap({
    "user-data"          = local.user_data
    "user-data-encoding" = "base64"
    }) : tomap({
    "user-data" = local.user_data
  })

  # A metadata value holds at most 256 KB
  # (https://cloud.google.com/compute/docs/metadata/setting-custom-metadata#limitations).
  user_data_max_bytes = 262144
}

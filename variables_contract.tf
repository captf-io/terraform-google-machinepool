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

# Contract inputs of the machinepool role, in contract order, with the
# contract's types: https://captf.io/docs/module-author/contract/v1alpha1/common.html
# and https://captf.io/docs/module-author/contract/v1alpha1/machinepool.html

# Read only by its own validation.
# tflint-ignore: terraform_unused_declarations
variable "captf_contract" {
  description = "Contract version the controller generated the root module for."
  type        = string

  validation {
    condition     = var.captf_contract == "v1alpha1"
    error_message = "captf_contract must be \"v1alpha1\": this module implements the v1alpha1 machinepool role only."
  }
}

variable "captf_cluster" {
  description = "The owning CAPI Cluster."
  type = object({
    name      = string
    namespace = string
  })
}

variable "captf_object" {
  description = "The TerraformMachinePool being reconciled."
  type = object({
    kind      = string
    name      = string
    namespace = string
  })
}

variable "captf_cluster_outputs" {
  description = "The cluster role's exports (schema captf.io/gcp-cluster/v1), or {} for an externally managed TerraformCluster."
  type        = any

  validation {
    condition     = try(length(var.captf_cluster_outputs) == 0, false) || try(var.captf_cluster_outputs.schema == "captf.io/gcp-cluster/v1", false)
    error_message = "captf_cluster_outputs must be exports of schema captf.io/gcp-cluster/v1 (from the gcp-cluster module) or {}: the TerraformCluster runs a different cluster module."
  }
}

variable "captf_tags" {
  description = "Fixed captf.io/* tags the controller sets; applied as GCP labels to the instance template, its disks and every instance."
  type        = map(string)
}

variable "machinepool_name" {
  description = "Name of the owning CAPI MachinePool; names the group and its instances."
  type        = string
}

variable "replicas" {
  description = "Desired capacity of the group: authoritative without autoscaling, the observed and clamped value with it."
  type        = number

  validation {
    condition     = var.replicas >= 0 && floor(var.replicas) == var.replicas
    error_message = "replicas must be a whole number of at least 0."
  }
}

variable "bootstrap_data" {
  description = "Base64 of the bootstrap Secret's value: cloud-config or Ignition, possibly gzipped. Rotates every few minutes."
  type        = string
  sensitive   = true
}

variable "bootstrap_format" {
  description = "Format of the decoded bootstrap payload: cloud-config or ignition."
  type        = string

  validation {
    condition     = contains(["cloud-config", "ignition"], var.bootstrap_format)
    error_message = "bootstrap_format must be cloud-config or ignition."
  }
}

variable "failure_domains" {
  description = "MachinePool.spec.failureDomains: the zones to spread over, or [] for the cluster's."
  type        = list(string)
}

variable "cluster_failure_domains" {
  description = "The cluster's failure domain names (zones), used when failure_domains is []."
  type        = list(string)
}

variable "kubernetes_version" {
  description = "MachinePool.spec.template.spec.version, possibly with a +rke2rN suffix; substituted into image placeholders, so a change rolls the pool."
  type        = string
  default     = null
}

variable "node_labels" {
  description = "MachinePool.spec.template.metadata.labels: registered by the kubelet of every new instance."
  type        = map(string)

  # The labels are written into a boot script, so only label syntax is
  # accepted (https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#syntax-and-character-set).
  validation {
    condition = alltrue([
      for k, v in var.node_labels :
      can(regex("^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$", k)) &&
      can(regex("^([A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?)?$", v))
    ])
    error_message = "node_labels must be Kubernetes labels: [prefix/]name keys and values of at most 63 characters from [A-Za-z0-9-_.]."
  }
}

variable "autoscaling" {
  description = "Parsed from the MachinePool's autoscaler annotations: enabled means the GCE autoscaler owns the desired count between min and max."
  type = object({
    enabled = bool
    min     = number
    max     = number
  })
}

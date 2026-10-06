<h1 align="center">
  <a href="https://captf.io/"><img
    src="https://captf.io/assets/readme/mark.svg"
    width="72" height="72" alt="CAPTF"></a>
  <br>
  terraform-google-machinepool
</h1>

<p align="center">The CAPTF machine pool module for Google Cloud</p>

<p align="center">
  <a href="https://github.com/captf-io/terraform-google-machinepool/actions/workflows/ci.yml"><img
    src="https://img.shields.io/github/actions/workflow/status/captf-io/terraform-google-machinepool/ci.yml?branch=main&amp;label=build&amp;labelColor=161B3A&amp;style=flat-square"
    alt="build"></a>
  <a href="https://captf.io/docs/module-author/contract/index.html"><img
    src="https://img.shields.io/static/v1?label=contract&amp;message=v1alpha1&amp;color=A974FF&amp;labelColor=161B3A&amp;style=flat-square"
    alt="contract v1alpha1"></a>
  <a href="https://captf.io/docs/"><img
    src="https://img.shields.io/static/v1?label=docs&amp;message=captf.io&amp;color=5B8CFF&amp;labelColor=161B3A&amp;style=flat-square"
    alt="docs captf.io"></a>
  <a href="https://github.com/captf-io/terraform-google-machinepool/blob/main/LICENSE.md"><img
    src="https://img.shields.io/static/v1?label=license&amp;message=Apache-2.0&amp;color=FFD84D&amp;labelColor=161B3A&amp;style=flat-square"
    alt="license Apache-2.0"></a>
</p>

> [!NOTE]
> **Pre-release.** CAPTF is `v1alpha1`: its API and its
> [module contract](https://captf.io/docs/module-author/contract/index.html)
> may still change between releases.

The `machinepool` role of the CAPTF modules for Google Cloud: the
Terraform/OpenTofu root module behind `TerraformMachinePool`. It creates one
regional managed instance group per Cluster API MachinePool, with an optional
GCE autoscaler. Contract:
<https://captf.io/docs/module-author/contract/v1alpha1/machinepool.html>.

This repository holds the module code. The image
`ghcr.io/captf-io/module-images/gcp-machinepool` is built and published by
[module-images](https://github.com/captf-io/module-images) from this repository's releases.

## Using it

CAPTF runs this module from the module image `ghcr.io/captf-io/module-images/gcp-machinepool`:
set the image on a `TerraformMachinePool`'s `spec.source.image`, and the
controller renders every input. The module is also published to the Terraform
Registry as `captf-io/machinepool/google` and can be called directly:

```hcl
module "machinepool" {
  source  = "captf-io/machinepool/google"
  version = "~> 0.1"

  # The contract inputs the controller would render (captf_contract,
  # captf_cluster, captf_object, captf_tags, ...; see Inputs), and any
  # user variables.
}
```

Called directly, the module is a CAPTF root module first:

- it configures its own `provider "google"` block, so the calling
  module cannot use `count`, `for_each` or `depends_on` on it, and the
  provider takes its credentials from the environment (see Identity
  Secret);
- its providers are pinned to exact versions (`versions.tf`), which the
  calling configuration has to accept;
- you set the `captf_*` inputs yourself.

## What it creates

| Resource | Type | When |
| --- | --- | --- |
| `pool_instance_template` | `google_compute_region_instance_template` | Always: everything an instance is made of except the bootstrap payload |
| `pool_instance_group_manager` | `google_compute_region_instance_group_manager` | Always: the group over the pool's zones; holds the bootstrap payload in its all-instances config |
| `pool_autoscaler` | `google_compute_region_autoscaler` | While the MachinePool's autoscaler annotations enable autoscaling with a maximum above 0 |
| `pool_default_zones` | `terraform_data` | Always: the cluster's zones at the first apply, pinned, for a pool without its own failure domains |

A data source lists the group's members on every refresh.

Pool instances are workers: the cluster's worker service account and network
tags, no external IP, Shielded VM, OS Login, project SSH keys blocked, the
serial port off, and Spot VMs with `spot`.

## Prerequisites

- **A gcp-cluster TerraformCluster**, whose exports give the project, region,
  subnetwork, worker service account and network tags; or
  `external_cluster_exports` for an externally managed one.
- **A node image per Kubernetes version**, named so that `image` can carry a
  `{version}`, `{semver}` or `{slug}` placeholder (below), with cloud-init for
  `node_labels`.
- **A cloud controller manager** (cloud-provider-gcp): `provider_id_list`
  holds what it writes to `Node.spec.providerID`; see the
  [machine README](https://github.com/captf-io/terraform-google-machine#prerequisites).
- **Quotas**: CPUs of `machine_type`'s family for the pool's size plus one
  surge instance per zone during a roll.
- **Permissions of the identity**: see the role table in the
  [cluster README](https://github.com/captf-io/terraform-google-cluster#prerequisites).

## Inputs

Contract inputs used: `machinepool_name` (names), `replicas` (the target size
without autoscaling), `bootstrap_data` and `bootstrap_format` (user-data),
`failure_domains` and `cluster_failure_domains` (zones), `kubernetes_version`
(image placeholders), `node_labels` (kubelet registration), `autoscaling`
(the autoscaler), `captf_cluster_outputs` (exports), `captf_cluster` and
`captf_object` (names, descriptions), `captf_tags` (labels).
`captf_contract` is validated.

User variables (`TerraformMachinePool.spec.variables`):

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `additional_network_tags` | `list(string)` | `[]` | Extra network tags for the pool's instances, on top of the cluster's node and role tags. |
| `additional_tags` | `map(string)` | `{}` | Extra GCP labels for the pool's instances, their boot disks and the instance template. Keys and values must already be valid GCP labels; the captf-io_ keys are reserved for captf_tags, which win. |
| `autoscaling_initialization_seconds` | `number` | `300` | Seconds a new instance needs to boot and join before the autoscaler reads its CPU; 300 covers image boot, cloud-init and kubeadm join. |
| `autoscaling_target_cpu_percent` | `number` | `60` | Average CPU utilization, in percent, the autoscaler keeps the pool at while the MachinePool's autoscaler annotations enable autoscaling. 60 leaves headroom for a node to fail. |
| `boot_disk_kms_key_id` | `string` | `null` | Cloud KMS key (projects/.../cryptoKeys/...) that encrypts the boot disk. Null uses Google-managed encryption; the Compute Engine service agent needs encrypt and decrypt on the key. |
| `boot_disk_size_gib` | `number` | `50` | Boot disk size in GiB: room for the image, container images and logs. |
| `boot_disk_type` | `string` | `"pd-balanced"` | Boot disk type. pd-balanced suits the default N2 machine type; C3, N4 and newer series need hyperdisk-balanced. |
| `can_ip_forward` | `bool` | `false` | Let the instances send and receive packets for other addresses, as CNIs that route pod CIDRs through GCP routes need. Off by default. |
| `external_cluster_exports` | `any` | `null` | Exports (schema captf.io/gcp-cluster/v1) to use when the TerraformCluster is externally managed and captf_cluster_outputs is {}. Ignored otherwise. |
| `image` | `string` | `null` | Boot image: a name, projects/<p>/global/images/<image> or a self link, with {version}, {semver}, {slug} or {fullslug} (v1.33.4, 1.33.4, v1-33-4, v1-33-4-rke2r1) so a kubernetes_version change rolls the pool; {fullslug} when the version has a +suffix. Required. |
| `machine_type` | `string` | `"n2-standard-4"` | Machine type of the pool's instances: 4 vCPU and 16 GiB by default. |
| `secure_boot` | `bool` | `true` | Shielded VM Secure Boot. On by default; turn it off only for images whose kernel modules are unsigned (some GPU drivers). |
| `spot` | `bool` | `false` | Run the pool on Spot VMs: cheaper, preemptible at any time; a preempted instance stops and the group repairs it. Off by default. |

## Outputs

| Name | Value |
| --- | --- |
| `provider_id` | The group's ID, `projects/<p>/regions/<r>/instanceGroupManagers/<name>` |
| `provider_id_list` | `gce://<project>/<zone>/<instance>` of every member that is not going away, whatever its state, sorted |
| `replicas` | The group's target size, as observed: the autoscaler's while it scales |
| `instances` | Per member: `provider_id`, `instance_id` (the instance name), `addresses = []`, `failure_domain` (zone), `state` (health enum) |
| `health` | Below |

`provider_id_list` keeps stopped members (Compute Engine `TERMINATED`):
dropping one would make CAPI delete its Node. Only a member whose status is
`DEPROVISIONING` (being torn down) leaves the list. The member listing has no
addresses, so `instances[*].addresses` is empty.

Non-contract outputs: `autoscaler_id`, `dropped_node_labels`, `instance_group_manager_id`,
`instance_template_id`.

## Exports

Reads the cluster's `captf.io/gcp-cluster/v1` exports (see
[the cluster README](https://github.com/captf-io/terraform-google-cluster#exports)); exports nothing.

## Identity Secret

The same Secret as the cluster role; see
[examples/identity.yaml](https://github.com/captf-io/terraform-google-machinepool/blob/main/examples/identity.yaml).

## Lifecycle

| Change | What happens |
| --- | --- |
| `bootstrap_data` (rotates about every 7.5 minutes with kubeadm) | The group's all-instances metadata is updated in place: a `REFRESH` that never restarts or replaces an instance. New instances boot with the current token; cloud-init runs once per instance, so existing ones are untouched. |
| `kubernetes_version` | The image placeholder changes the image, so a new instance template is created; the group's `PROACTIVE` update policy replaces every instance, one surge instance per zone at a time, none removed first. A version with a build suffix (`v1.31.4+rke2r2`) needs `{fullslug}` in `image` (a precondition), so a suffix-only upgrade rolls too. |
| `node_labels` | The all-instances metadata changes in place: new instances register the new labels; existing ones keep theirs. |
| `replicas` (autoscaling off) | The group's target size. |
| `replicas` (autoscaling on) | Ignored: `target_size` is null, which leaves the autoscaler's count alone. |
| `autoscaling` on or off | Creates or deletes the autoscaler; turning it off makes `replicas` authoritative again. A maximum of 0 means no autoscaler and a target size of 0. |
| `failure_domains` | Replaces the group (`distribution_policy_zones` is ForceNew): every instance is replaced at once. |
| `cluster_failure_domains` (the cluster's zones change) | Nothing: a pool without its own failure domains keeps the zones it was created with. Set `failure_domains` to move it, which replaces the group. |
| `captf_tags` or `additional_tags` | The all-instances config relabels every instance in place. The template's own and its disks' labels are ForceNew, so they are `ignore_changes`: the template keeps the labels it was created with. |
| Any other template variable (`machine_type`, `boot_disk_*`, `spot`, `secure_boot`, `additional_network_tags`, `can_ip_forward`) | A new instance template; the group updates instances with the least disruptive action Compute Engine allows, which may replace them. |

There is no drain: MachinePool Machines are out of scope for the contract,
so replaced or scaled-in instances are not drained first.

## Bootstrap

`node_labels` must reach the kubelet's registration, which the module does
without parsing the payload. With labels to register, the user-data is a
MIME multipart message:

1. a `text/cloud-boothook` part with the node-labels fragment every CAPTF
   pool module shares (CONVENTIONS.md section 13). For each of
   `/etc/default/kubelet` and `/etc/sysconfig/kubelet` whose directory
   exists, it replaces a block marked `# captf-node-labels` with a
   `KUBELET_EXTRA_ARGS` line that keeps the image's value and appends
   `--node-labels=<sorted labels>` (kubeadm); it writes
   `/etc/rancher/rke2/config.yaml.d/50-captf-node-labels.yaml` with
   `node-label+:`, which appends to the bootstrap's own list (RKE2). It is
   idempotent, since boothooks run on every boot;
2. the bootstrap payload, unchanged, as a base64 part: `application/x-gzip`
   when gzipped (cloud-init decompresses it), else `text/plain` (cloud-init
   detects `#cloud-config` or `## template: jinja`).

The message is sent base64 with `user-data-encoding=base64`. Labels in the
`kubernetes.io` and `k8s.io` namespaces that the kubelet may not set (for
example `node-role.kubernetes.io/*`) are dropped; the kubelet would refuse to
start with them. The `dropped_node_labels` output lists them. Labels must
match Kubernetes label syntax (validated: they end up in a shell script).

| `bootstrap_format` | Labels to register | Sent as |
| --- | --- | --- |
| `cloud-config` | none | the payload, base64, `user-data-encoding=base64` |
| `cloud-config` | some | the multipart message above |
| `ignition` | none | the decoded payload; gzipped Ignition is refused |
| `ignition` | some | refused by a precondition: Ignition has no boothook |

The user-data must fit the 256 KB metadata value limit (a precondition).

## Tags

The group's all-instances config (so every instance) carries
`merge(additional_tags, captf_tags)` as GCP labels, kept current in place,
with the mapping of the [cluster README](https://github.com/captf-io/terraform-google-cluster#tags). The
instance template and its boot disks carry the same labels as of the
template's creation: their labels are ForceNew, so they are not updated. The group
and the autoscaler cannot carry labels; their description names the pool.

## Health

From the group's target size and its members' status (the
[machine README](https://github.com/captf-io/terraform-google-machine#health) maps each status):

| Situation | `state` | `healthy` | `reasons` |
| --- | --- | --- | --- |
| The group no longer exists | `terminated` | `false` | `["InstanceGroupNotFound"]` |
| Target size 0 (and no autoscaler minimum above 0 still to reach) | `running` | `true` | `[]` |
| No members yet | `pending` | `false` | `["NoMembers"]` |
| A member degraded, stopped or unknown | the worst of those three | `false` | `"<reason>:<instance>"` per affected member, then per starting member, plus `ScalingInProgress` while the count differs |
| Otherwise | `running` | `true` only when every member runs and their number equals the target size | the starting members, plus `ScalingInProgress` while the count differs |

A starting member never makes the pool `pending` (machinepool.md "Deriving
group health"). A member whose status means deletion (`DEPROVISIONING`) is
not a member.

## Limitations

- A precondition caps the pool at 500 instances (`replicas`, or the
  autoscaler's maximum): the member listing is one unpaged request, and
  `regionInstanceGroups.listInstances` returns at most 500.
- Changing `failure_domains` replaces the group at once. Without them, the
  pool keeps the cluster's zones of its first apply, even if the cluster
  later drops one.
- The group keeps zones balanced (`EVEN` shape, `PROACTIVE` redistribution)
  and may delete an instance to rebalance; nothing drains it.
- Ignition pools cannot register `node_labels`.
- Boot disk labels and the template's labels keep the values the template was
  created with (they are ForceNew); instance labels follow `captf_tags` and
  `additional_tags` through the all-instances config.
- `replicas` reads 0 once the group no longer exists; `health` reports it.

## Exceptions

- Any instance-template change rolls the pool: every template argument is
  ForceNew, so a change of `machine_type`, `boot_disk_*`, `spot`,
  `secure_boot`, `additional_network_tags` or `can_ip_forward` creates a new
  template, and the group updates its instances with the least disruptive
  action Compute Engine allows, which may replace them (CONVENTIONS.md
  section 13 lists only `kubernetes_version`).
- A `kubernetes_version` change rolls through the image name, not
  `terraform_data.kubernetes_version_roll`: a version-only template change
  would be a metadata REFRESH under `minimal_action = "REFRESH"` and roll
  nothing. So `image` must carry a version placeholder, and `{fullslug}`
  when the version has a `+rke2rN` suffix (preconditions), so a suffix-only
  upgrade rolls too.
- `tfcapi-lint` warning `pool/autoscaling-ignore-changes` is allowed: the
  module keeps the autoscaler's count without `ignore_changes`, by setting
  `target_size` to null while an autoscaler runs, else `var.replicas`.
  `target_size` is optional and computed, so null leaves the observed value
  alone and an apply never resets it. `ignore_changes` cannot express the
  disabled mode: it is static, and the alternative, an always-on autoscaler
  pinned to `min = max = replicas`, would keep an autoscaler on pools you
  size by hand and needs `max = 0` for an empty pool, which the autoscaler
  API does not document. The allowance is in this repository's
  `Makefile` (`TFCAPI_LINT_ALLOW`); the reason is also in
  [DESIGN.md](https://github.com/captf-io/terraform-google-machinepool/blob/main/DESIGN.md) decision 5.

## Examples

A MachinePool's TerraformMachinePool with this image (from
[examples/cluster-kubeadm.yaml](https://github.com/captf-io/terraform-google-machinepool/blob/main/examples/cluster-kubeadm.yaml)):

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: TerraformMachinePool
metadata:
  name: demo-pool-0
  labels:
    cluster.x-k8s.io/cluster-name: demo
spec:
  source:
    image: ghcr.io/captf-io/module-images/gcp-machinepool:v0.1.0-opentofu
  variables:
    image: projects/my-images/global/images/capi-ubuntu-2404-{slug}
```

## Developing

The host needs make, podman (or docker with `ENGINE=docker`), jq and Go.
Every other tool runs in a digest-pinned container. `make verify` is the
gate. `make help` lists the targets:

- `make fmt`: format the module with `terraform fmt` and `tofu fmt`, in place.
- `make fmt-check`: fail on any file the formatters would change.
- `make validate`: `init` and `validate` on both runtimes and on their floors
  (Terraform 1.5.7, OpenTofu 1.6.3).
- `make unit-test`: `terraform test` and `tofu test` with mocked providers.
- `make tflint`: tflint with the terraform ruleset (preset all) and the cloud
  ruleset.
- `make tfcapi-lint`: `tfcapi-lint module --strict`, built from `PROVIDER_DIR`
  (default `../cluster-api-provider-terraform`, a clone of
  [cluster-api-provider-terraform](https://github.com/captf-io/cluster-api-provider-terraform)
  next to this one); skipped when it is absent.
- `make scan`: trivy config over the repository; ignores live in
  `.trivyignore.yaml`.
- `make check-conventions`: the layout and tag checks (`hack/check-layout.sh`,
  `hack/check-tags.sh`) for CONVENTIONS.md.
- `make shellcheck`: shellcheck over `hack/` and every shell template.
- `make check-headers`, `make fix-headers`: check or add the Apache-2.0 license
  header.
- `make verify`: all of the above, in parallel groups.
- `make clean`: remove `build/`; keeps `.cache/` and `.tools/`.

Useful variables: `RUNTIMES=opentofu` (or `terraform`), `ENGINE=docker`,
`PROVIDER_DIR=<path>`.

<br>
<p align="center">
  <img
    src="https://captf.io/assets/readme/divider.svg"
    width="100%" height="4" alt="">
</p>
<p align="center">
  <a href="https://captf.io/"><img
    src="https://captf.io/assets/readme/mark.svg"
    width="40" height="40" alt="CAPTF"></a>
  <br>
  <a href="https://captf.io/docs/"
    ><b>Documentation</b></a> ·
  <a href="https://captf.io/docs/getting-started/quick-start.html"
    ><b>Quick start</b></a> ·
  <a href="https://github.com/captf-io/.github/blob/main/CONTRIBUTING.md"
    ><b>Contributing</b></a> ·
  <a href="https://github.com/captf-io/.github/blob/main/SECURITY.md"
    ><b>Security</b></a>
  <br>
  <sub>Built for
    <a href="https://cluster-api.sigs.k8s.io/">Cluster API</a>.
    <a href="https://github.com/captf-io/terraform-google-machinepool/blob/main/LICENSE.md"
    >Apache 2.0</a>.</sub>
</p>

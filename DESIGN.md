# Design: terraform-google-machinepool

Why this module looks the way it does. Each decision names the evidence it
rests on; anything not yet checked against a real project is listed under
"Unverified" and must be confirmed on the first reviewed apply.

Pins: `hashicorp/google` 8.5.0. Runtimes: Terraform >= 1.5, OpenTofu >= 1.6.
Conventions: [CONVENTIONS.md](CONVENTIONS.md). Contract:
<https://captf.io/docs/module-author/contract/v1alpha1/>.

Provider facts below were read from the provider at the pin: the schema
(`hack/tf-run.sh schema`) for attribute names and types, and the source at
`v8.5.0` (`google/services/compute/*.go`) for ForceNew, defaults, diff
suppression and API calls.

The CAPTF Google Cloud modules are three repositories, one for each role:
[terraform-google-cluster](https://github.com/captf-io/terraform-google-cluster),
[terraform-google-machine](https://github.com/captf-io/terraform-google-machine) and
[terraform-google-machinepool](https://github.com/captf-io/terraform-google-machinepool). This file covers the `machinepool` role and
the decisions shared with the others. Decision and Unverified numbers are the
same in all three repositories, so "decision 4" means the same everywhere; a
decision that concerns another role is a one-line pointer under its number.

## Scope

- One role here, `machinepool`. The other roles are the other two repositories ([cluster](https://github.com/captf-io/terraform-google-cluster), [machine](https://github.com/captf-io/terraform-google-machine)).
- Bring-your-own network: the VPC, subnetwork, proxy-only subnet and Cloud
  NAT exist before the cluster. The cluster role creates firewall rules, the
  API load balancer and node service accounts.
- The API load balancer is internal by default; external is opt-in with an
  explicit allowed-CIDR list.
- Node service accounts are created by default; variables take existing
  ones.

## Decisions

### 1. API load balancer: proxy, not passthrough

Concerns the cluster role: see [terraform-google-cluster DESIGN.md](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md#1-api-load-balancer-proxy-not-passthrough).

### 2. Firewall rules target service accounts

Concerns the cluster role: see [terraform-google-cluster DESIGN.md](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md#2-firewall-rules-target-service-accounts).

### 3. Node identities

Concerns the cluster role: see [terraform-google-cluster DESIGN.md](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md#3-node-identities).

### 4. Machine

Concerns the machine role: see [terraform-google-machine DESIGN.md](https://github.com/captf-io/terraform-google-machine/blob/main/DESIGN.md#4-machine).

### 5. Machine pool

- Regional instance template (`name_prefix` of at most 37 characters, as
  the provider appends a 26-character suffix beyond that;
  `create_before_destroy`) holds everything except the bootstrap payload.
  It has no `self_link_unique` in 8.5.0; `name_prefix` makes every new
  template's self link new.
- Regional managed instance group: the bootstrap payload lives in
  `all_instances_config.metadata`, so a rotation is a metadata REFRESH
  that never restarts or replaces an instance (cloud-init runs once per
  instance ID; new members get the current token).
- Update policy: `PROACTIVE`, `minimal_action = "REFRESH"`,
  `most_disruptive_allowed_action = "REPLACE"`. With REFRESH as the least
  action, a metadata change refreshes in place, and "if the Updater
  determines that the minimal action you specify is not enough to perform
  the update, it might perform a more disruptive action" (provider
  `minimal_action` description): a new image is replaced.
  `max_surge_fixed = number of zones` (the API's default for maxSurge) and
  `max_unavailable_fixed = 0`; "at least one of either maxSurge or
  maxUnavailable must be greater than 0" (Compute API).
- A Kubernetes version change must roll. The template's image must contain
  a version placeholder (`{version}`, `{semver}` or `{slug}`); a precondition
  enforces it when `kubernetes_version` is set. OPPORTUNISTIC alone never
  rolls existing instances, so it would break the contract.
- Desired count: `target_size = var.autoscaling.enabled ? null :
  var.replicas`. `target_size` is optional and computed, so null keeps the
  autoscaler's value and an apply never resets it (the provider sends
  `targetSize` on update only when it changes). `ignore_changes` cannot
  express the disabled mode without an always-on autoscaler. tfcapi-lint
  does not recognise this pattern and warns
  (`pool/autoscaling-ignore-changes`, allowed with this reason).
- Membership: `data.google_compute_region_instance_group` lists every
  instance (`instanceState: ALL`) in one request without pagination
  (`data_source_google_compute_region_instance_group.go`), and
  `listInstances` returns at most 500 per page ("Acceptable values are 0 to
  500, inclusive. (Default: 500)", Compute API discovery document): pools
  are limited to 500 members, documented. Stopped members (`TERMINATED`)
  stay in `provider_id_list`; only `DEPROVISIONING` members leave it.
- Pool health follows CONVENTIONS.md section 10: a gone group is
  terminated, a degraded, stopped or unknown member makes the pool that
  state, and a starting member never makes it pending (machinepool.md
  "Deriving group health"). An autoscaled group created empty is pending,
  not "scaled to zero", until a member exists: the autoscaler's minimum is
  its desired capacity then.
- `node_labels`: the shared node-labels fragment (CONVENTIONS.md section 13,
  embedded verbatim) in a MIME multipart user-data of a `text/cloud-boothook` part
  and the payload as an opaque base64 part (CONVENTIONS.md section 13),
  rendered from `templates/`. Labels must match Kubernetes label syntax
  (validated, as they are written into a shell script); kubernetes.io and
  k8s.io labels the kubelet may not set are dropped (its
  `KubeletLabels` and `KubeletLabelNamespaces`).
- Changing the zones replaces the group (`distribution_policy_zones` is
  ForceNew), all instances at once. Explicit `failure_domains` do so as
  documented. Without them the zones come from `cluster_failure_domains`,
  which changes whenever the cluster's zones do (every zone of the region by
  default), and every pool re-applies without approval: so a pool pins the
  cluster's zones at its first apply (`terraform_data` with
  `ignore_changes = [input]`), and a cluster zone change never replaces a
  pool.
- Size: a precondition caps `replicas` (or the autoscaler's maximum) at 500,
  the one page the member listing returns.
- An autoscaling maximum of 0 creates no autoscaler and sets a target size
  of 0, so the contract's `min = max = 0` never meets the autoscaler API.
- RKE2 node labels go to `config.yaml.d` as `node-label+:`: RKE2 merges
  later files over earlier ones, and `+` appends to the bootstrap's own
  list instead of replacing it.
- Versions with build metadata (`+rke2rN`): every placeholder but
  `{fullslug}` drops the suffix, so a suffix-only upgrade would not change
  the image and would never roll. A precondition requires `{fullslug}` when
  the version has a suffix.
- Labels: a template's `labels` (through `effective_labels`) and its disks'
  `labels` are ForceNew (`resource_compute_region_instance_template.go`), so
  a `captf_tags` change (a ClusterClass rebase rewrites
  `captf.io/template`) would create a new template and roll the pool. They
  are `ignore_changes`; `all_instances_config.labels`, updated in place,
  keeps every instance's labels current.
- Health while autoscaling: the group is created with no target size and
  the autoscaler grows it to its minimum, so "target size 0, no members"
  reads as scaled to zero only without an autoscaler minimum above 0;
  otherwise it is pending, and the pool is not marked provisioned before a
  member exists.

### 6. provider_id, addresses, health

- `gce://<project>/<zone>/<instance-name>`: cloud-provider-gcp v37.1.1
  `InstanceID` returns `<project>/<zone>/<name>` and `GetInstanceProviderID`
  prefixes `gce://`; `providerIDRE` is `^gce://([^/]+)/([^/]+)/([^/]+)$`
  (`providers/gce/gce_instances.go`, `gce_util.go`). Node names equal
  instance names.
- Health from `current_status`, every value of the v1 `Instance.status`
  enum: RUNNING → running; PENDING, PROVISIONING, STAGING → pending;
  PENDING_STOP, STOPPING, STOPPED, SUSPENDING, SUSPENDED, TERMINATED (GCP's
  word for stopped) → stopped; REPAIRING → degraded; DEPROVISIONING ("The
  instance is halted and we are performing tear down tasks like network
  deprogramming, releasing quota, IP, tearing down disks", Compute API) →
  terminated (reason `InstanceNotFound`); other → unknown (`UnknownState`).
  A pool whose group no longer exists is terminated (`InstanceGroupNotFound`); the README maps the group's health. The pool's
  group is `count = 1`: after an out-of-band delete, `apply -refresh-only` reads an empty tuple,
  where the references of a single resource would turn unknown and the outputs null;
  outputs read them through splats, because `one()` of the whole object
  would carry the sensitivity of its metadata into every output.

### 7. Labels

GCP label keys match `[a-z][a-z0-9_-]{0,62}` and values `[a-z0-9_-]{0,63}`:
no `.` or `/`. Mapping: lowercase, `.` to `-`, other invalid characters to
`_` (`captf.io/cluster` → `captf-io_cluster`); values lowercased, invalid
characters to `_`, longer than 63 characters cut to 54 plus `-` plus 8 hex
characters of the original's sha256. An empty `captf.io/template` stays
empty.

Labels are set explicitly on every labelable resource and on nested
labels (boot disk, `all_instances_config.labels`), never through provider
`default_labels`; `add_terraform_attribution_label = false`, so the labels
on a resource are exactly the documented ones. Not labelable in 8.5.0:
firewall rules, backend services, health checks, target proxies, unmanaged
instance groups, managed instance groups, autoscalers, service accounts and
IAM members.

Their descriptions name the owning object (`CAPTF cluster <ns>/<name>`),
never `captf_tags`: `description` is ForceNew on addresses, forwarding
rules, target proxies, instance groups and managed instance groups, and
`captf.io/template` changes on a ClusterClass rebase. The earlier design's
`jsonencode(var.captf_tags)` descriptions would have replaced them, the
API address included.

### 8. Credentials

Identity Secret: `GOOGLE_CREDENTIALS` (service account key JSON or an
`external_account` JSON), `GOOGLE_PROJECT`, `GOOGLE_REGION`; or a
`credentials.json` file key with
`GOOGLE_APPLICATION_CREDENTIALS=/var/run/captf/credentials/credentials.json`.
The provider block sets `project` and `region` from variables (cluster) or
exports (machine, pool); null falls back to the environment. The cluster
reads the effective values with `data.google_client_config` and fails a
postcondition when either is empty.

## Exports

A pool reads the cluster's `captf.io/gcp-cluster/v1` exports as
`captf_cluster_outputs` (or `external_cluster_exports` for an externally
managed TerraformCluster) and exports nothing. The schema, and why the
API registration targets are per-zone instance groups, are in
[DESIGN.md of terraform-google-cluster](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md#exports).

## Unverified

**3.** Which changes the MIG classifies as REFRESH versus REPLACE, beyond "a
different image needs REPLACE": in particular that an
`all_instances_config` label or metadata change is a REFRESH.

**5.** That DEPROVISIONING appears only while an instance is deleted, not while
it stops; a stopping pool member in that state would leave
`provider_id_list` early.

**6.** cloud-init's handling of a base64 `application/x-gzip` part inside the
multipart user-data, and of a `text/plain` part holding a
`## template: jinja` payload.

**7.** That the managed instance group repairs a preempted (stopped) Spot VM.

Verified since the first draft: the member listing's page size is 500.

Items 1, 2, 4, 8-11 concern the cluster and machine roles; see their DESIGN.md.

## Rejected alternatives

- MIG update policy OPPORTUNISTIC (never rolls).
- `ignore_changes = [target_size]` (cannot track `replicas` with
  autoscaling off).
- Provider `default_labels` (misses nested labels; untestable).

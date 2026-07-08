## 2026-07-04 - Optimize Subprocess and Ray Client Calls
**Learning:** `list_ray_nodes()` launches a python subprocess that runs `ray.init()`, taking significant time. Redundantly querying Ray nodes across `count_live_nodes`, `live_worker_node_ips`, and `node_ip_to_id` adds up rapidly, particularly during frequent reconcile loops.
**Action:** Always fetch stateful information (like ray nodes) once and pass the result down to helper functions rather than allowing helpers to implicitly fetch their own dependencies.

## 2024-07-08 - Batching list_ray_nodes in Request Handlers
**Learning:** Within the same request lifecycle (e.g. `index` or `api_status`), `list_ray_nodes()` was being called multiple times: once indirectly through `reconcile_cluster` and again directly or via `_cluster_payload`. Because `list_ray_nodes()` executes an expensive subprocess spawning and a `ray.init()` call, this duplication was highly inefficient and caused unnecessary bottlenecks in endpoint latency.
**Action:** Extract expensive data-fetching calls like `list_ray_nodes()` to the top of the request handler or entry point, and pass the fetched `nodes` downwards through helper functions like `reconcile_cluster` and `_cluster_payload` using optional parameters.

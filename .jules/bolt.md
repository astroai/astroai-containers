## 2026-07-04 - Optimize Subprocess and Ray Client Calls
**Learning:** `list_ray_nodes()` launches a python subprocess that runs `ray.init()`, taking significant time. Redundantly querying Ray nodes across `count_live_nodes`, `live_worker_node_ips`, and `node_ip_to_id` adds up rapidly, particularly during frequent reconcile loops.
**Action:** Always fetch stateful information (like ray nodes) once and pass the result down to helper functions rather than allowing helpers to implicitly fetch their own dependencies.
## 2024-07-11 - Cache Ray Subprocess Calls
**Learning:** In the Ray Manager app, Ray subprocess calls (like `ray status` and `ray.init` / `ray.nodes()`) are expensive and can slow down the FastAPI server during status polling.
**Action:** Always batch or cache Ray interaction state, like passing down the results of `list_ray_nodes()` to downstream functions (e.g., `ray_running` or `reconcile_cluster`) instead of querying Ray redundantly.

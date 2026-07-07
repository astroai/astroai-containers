## 2026-07-04 - Optimize Subprocess and Ray Client Calls
**Learning:** `list_ray_nodes()` launches a python subprocess that runs `ray.init()`, taking significant time. Redundantly querying Ray nodes across `count_live_nodes`, `live_worker_node_ips`, and `node_ip_to_id` adds up rapidly, particularly during frequent reconcile loops.
**Action:** Always fetch stateful information (like ray nodes) once and pass the result down to helper functions rather than allowing helpers to implicitly fetch their own dependencies.

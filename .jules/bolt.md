
## 2024-07-02 - Batching Ray node fetching
**Learning:** Calling `list_ray_nodes()` in `ray_cluster.py` is expensive because it spawns a subprocess to run a Python script that calls `ray.init()` and `ray.nodes()`. Functions like `live_worker_node_ips` and `node_ip_to_id` were repeatedly invoking this, causing redundant expensive calls during a single reconciliation cycle in `reconcile_cluster`.
**Action:** When working with Ray cluster state, fetch nodes once and pass the cached list down to helper functions to avoid redundant subprocess spawns and repeated initialization of Ray.

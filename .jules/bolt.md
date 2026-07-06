## 2026-07-06 - Batching Ray Subprocess Calls
**Learning:** `list_ray_nodes()` calls a heavy `ray.init()` subprocess. Calling it redundantly inside loops or separate helper functions (like `live_worker_node_ips` and `count_live_nodes` back to back) introduces significant performance penalties.
**Action:** When multiple node properties are required in the same scope, always fetch nodes once with `list_ray_nodes()` and pass the cached list to helper functions.

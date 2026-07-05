## 2024-07-05 - Batching Ray Subprocess Calls
**Learning:** Redundantly calling `ray.init()` or spawning subprocesses for Ray interactions (e.g., `list_ray_nodes()`) is extremely expensive and causes performance bottlenecks during cluster state reconciliation.
**Action:** Fetch Ray state (like nodes) once at the top level and pass it down to helper functions rather than letting each helper invoke the subprocess separately.

# Conda env locks (improc image)

These `@EXPLICIT` lock files pin the exact package tarballs for the improc
conda environments. The improc Dockerfile installs from them with
`micromamba create -f <lock>`, so image builds **skip conda-forge repodata
downloads and the solver entirely** — they just fetch the pinned tarballs.

| Lock | Env | Contents |
|------|-----|----------|
| `sxpp.lock` | `/opt/astroai/conda/sxpp` | sourcextractor++ 1.1.0 (astrorama + conda-forge) |
| `skymaker.lock` | `/opt/astroai/conda/skymaker` | astromatic-skymaker 3.10.5 (binary is `sky`) |
| `ngmix.lock` | `/opt/astroai/conda/ngmix` | ngmix 2.4.1 (no PyPI release) |

## Regenerating a lock

The images already contain the built envs, so regenerate from a built image
(or from a scratch `micromamba create`):

```bash
docker run --rm --entrypoint bash images.canfar.net/astroai/improc:<tag> \
  micromamba env export -p /opt/astroai/conda/skymaker --explicit \
  > config/conda/skymaker.lock
```

The URL lines pin both version and build string; version bumps mean
regenerating the lock (and the Dockerfile has no version ARGs for these envs —
the lock is the single source of truth). `micromamba` and `mamba` are the same
binary here (both use the libmamba solver), so either command works.

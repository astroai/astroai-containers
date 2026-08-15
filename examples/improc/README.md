# Synthetic field simulation: Stuff → SkyMaker → SExtractor

This example runs the classic AstrOmatic simulation workflow inside the
[improc image](../../dockerfiles/improc/Dockerfile):

1. **Stuff** generates a realistic galaxy catalog (positions, magnitudes,
   bulge/disk morphologies) from number counts, SEDs and cosmological models.
2. **SkyMaker** (`sky`) turns that catalog — plus a procedurally generated
   stellar field — into a synthetic FITS image with PSF, background and noise.
3. **SExtractor** detects and measures the sources in the simulated image,
   closing the loop: you can now test pipelines against data with a known
   ground truth.

## Usage

```bash
# inside the improc container
bash simulate_field.sh
```

Outputs land in `./sim`:

| File | Contents |
|---|---|
| `sim.list` | Galaxy catalog from Stuff (SkyMaker list format, code 200) |
| `sim_r.fits` | 2048×2048 simulated image (0.2″/pix, ~6.8′ field) |
| `sim_r.list` | Catalog of sources SkyMaker actually rendered |
| `sim_r.cat` | SExtractor detection catalog (255 sources with default settings) |
| `stuff.conf`, `sky.conf`, `default.*` | Generated configuration files |

## Notes

- **Stars**: Stuff only generates galaxies. SkyMaker adds stars itself from
  the `STARCOUNT_ZP`/`MAG_LIMITS` keywords in `sky.conf`.
- **Matching sky/stuff**: keep `FIELD_SIZE` and `PIXEL_SIZE` consistent between
  the two configurations, and `COORD_TYPE PIXEL` in Stuff so its catalog
  coordinates map directly onto SkyMaker pixels.
- **Ground truth**: `sim_r.list` (SkyMaker) is the truth table — the
  *detected* sources in `sim_r.cat` can be cross-matched to it (e.g. with
  `stilts tmatch2` or `astropy`'s `SkyCoord`/`match_to_catalog_sky`).
- **Multiple bands**: set `PASSBAND_OBS` (Stuff) to a comma-separated list
  (e.g. `sdss/g,sdss/r,sdss/i`) to get one catalog per band, then run `sky`
  per band with matching `IMAGE_NAME`.

See `sky -d` / `stuff -d` in the container for every available keyword.

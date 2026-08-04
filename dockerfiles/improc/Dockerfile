# syntax=docker/dockerfile:1
# AstroAI improc: astronomy FITS/HDF5 image-processing CLIs on base.
# Headless. Apt for native CLIs; source/binaries where Debian lags; uv for
# science Python; micromamba for sourcextractor++ (astrorama).
# MaxiMask/MaxiTrack: isolated TF venv (/opt/astroai/venv/maximask).

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG TAG=local
ARG GNUASTRO_VERSION=0.24
ARG FITS2IDIA_VERSION=0.1.15
ARG IMFIT_VERSION=1.9.0
ARG PQRS_VERSION=0.3.2
ARG SOURCEXTRACTOR_VERSION=1.1.0

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------
FROM debian:trixie-slim AS casutools-build
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libcfitsio-dev wcslib-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
COPY dockerfiles/improc/vendor/casutools-1.0.43.tar.gz /tmp/
RUN tar xzf casutools-1.0.43.tar.gz \
    && cd casutools-1.0.43 \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/casutools*

FROM debian:trixie-slim AS gnuastro-build
ARG GNUASTRO_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl \
    libcfitsio-dev libgsl-dev libfftw3-dev libgit2-dev libjpeg-dev \
    libtiff-dev zlib1g-dev libtool-bin wcslib-dev libcurl4-openssl-dev \
    libbz2-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
RUN curl -fsSL -o gnuastro.tar.gz \
      "https://ftp.gnu.org/gnu/gnuastro/gnuastro-${GNUASTRO_VERSION}.tar.gz" \
    && tar xzf gnuastro.tar.gz \
    && cd "gnuastro-${GNUASTRO_VERSION}" \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/gnuastro*

FROM debian:trixie-slim AS fits2idia-build
ARG FITS2IDIA_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates cmake curl \
    libcfitsio-dev libhdf5-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
RUN curl -fsSL -o fits2idia.tar.gz \
      "https://github.com/CARTAvis/fits2idia/archive/refs/tags/v${FITS2IDIA_VERSION}.tar.gz" \
    && tar xzf fits2idia.tar.gz \
    && cd "fits2idia-${FITS2IDIA_VERSION}" \
    && mkdir build && cd build \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr/local .. \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/fits2idia*

# ---------------------------------------------------------------------------
# Final image
# ---------------------------------------------------------------------------
FROM ${REGISTRY}/${OWNER}/base:${TAG}

ARG GNUASTRO_VERSION
ARG FITS2IDIA_VERSION
ARG IMFIT_VERSION
ARG PQRS_VERSION
ARG SOURCEXTRACTOR_VERSION

LABEL org.opencontainers.image.title="AstroAI Improc" \
      org.opencontainers.image.description="Astronomy image-processing CLIs (FITS/HDF5)" \
      io.canfar.skaha.session.type="headless"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Native CLIs (Debian trixie). Prefer apt when versions track upstream.
# SCAMP: pin 2.15 from sid (stable is still 2.14; single-package, no dep cascade).
RUN printf '%s\n' \
      'deb http://deb.debian.org/debian sid main' \
      > /etc/apt/sources.list.d/sid.list \
    && printf '%s\n' \
      'Package: *' \
      'Pin: release a=unstable' \
      'Pin-Priority: 100' \
      '' \
      'Package: scamp' \
      'Pin: release a=unstable' \
      'Pin-Priority: 990' \
      > /etc/apt/preferences.d/sid-scamp \
    && apt-get update && apt-get install -y --no-install-recommends \
    source-extractor \
    swarp \
    psfex \
    scamp \
    stiff \
    missfits \
    fitscut \
    fitspng \
    fitsh \
    fitsverify \
    libcfitsio-bin \
    iraf \
    iraf-noao \
    funtools \
    montage \
    montage-gridtools \
    munipack \
    qfits-tools \
    wcstools \
    weightwatcher \
    theli \
    astrometry.net \
    hdf5-tools \
    h5utils \
    default-jre-headless \
    imagemagick \
    libmagickcore-7.q16-10-extra \
    unzip \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/source-extractor /usr/local/bin/sextractor \
    && if [[ -x /usr/bin/SWarp ]] && [[ ! -e /usr/local/bin/swarp ]]; then \
         ln -sf /usr/bin/SWarp /usr/local/bin/swarp; \
       fi \
    && if [[ -x /usr/bin/swarp ]] && [[ ! -e /usr/local/bin/SWarp ]]; then \
         ln -sf /usr/bin/swarp /usr/local/bin/SWarp; \
       fi \
    && scamp -v 2>&1 | head -1 | grep -q '2\.15' \
    || { echo "expected SCAMP 2.15 from sid" >&2; scamp -v 2>&1 | head -1; exit 1; } \
    && rm -f /etc/apt/sources.list.d/sid.list /etc/apt/preferences.d/sid-scamp

# Source-built tools
COPY --from=casutools-build /usr/local/ /usr/local/
COPY --from=gnuastro-build /usr/local/ /usr/local/
COPY --from=fits2idia-build /usr/local/ /usr/local/
RUN ldconfig

# GALFIT binary (+ legacy ncurses5 for the Carnegie build)
RUN apt-get update && apt-get install -y --no-install-recommends wget ca-certificates \
    && cd /tmp \
    && wget -q http://deb.debian.org/debian/pool/main/n/ncurses/libtinfo5_6.4-4_amd64.deb \
    && wget -q http://deb.debian.org/debian/pool/main/n/ncurses/libncurses5_6.4-4_amd64.deb \
    && apt-get install -y --no-install-recommends \
         ./libtinfo5_6.4-4_amd64.deb ./libncurses5_6.4-4_amd64.deb \
    && wget -q https://users.obs.carnegiescience.edu/peng/work/galfit/galfit3-debian64.tar.gz \
    && tar xzf galfit3-debian64.tar.gz \
    && install -m 755 galfit /usr/local/bin/galfit \
    && rm -rf /tmp/galfit* /tmp/libtinfo5*.deb /tmp/libncurses5*.deb \
    && rm -rf /var/lib/apt/lists/*

# Imfit prebuilt binaries
ARG IMFIT_VERSION
RUN cd /opt \
    && wget -q "https://www.mpe.mpg.de/~erwin/resources/imfit/binaries/imfit-${IMFIT_VERSION}-linux-64.tar.gz" \
    && tar xzf "imfit-${IMFIT_VERSION}-linux-64.tar.gz" \
    && rm "imfit-${IMFIT_VERSION}-linux-64.tar.gz" \
    && ln -sfn "imfit-${IMFIT_VERSION}" /opt/imfit \
    && for f in imfit imfit-mcmc makeimage; do \
         ln -sf "/opt/imfit/${f}" "/usr/local/bin/${f}"; \
       done

# pqrs (Parquet CLI)
ARG PQRS_VERSION
RUN cd /tmp \
    && wget -q "https://github.com/manojkarthick/pqrs/releases/download/v${PQRS_VERSION}/pqrs-${PQRS_VERSION}-x86_64-unknown-linux-gnu.zip" \
    && unzip -q "pqrs-${PQRS_VERSION}-x86_64-unknown-linux-gnu.zip" \
    && install -m 755 "pqrs-${PQRS_VERSION}-x86_64-unknown-linux-gnu/bin/pqrs" /usr/local/bin/pqrs \
    && rm -rf /tmp/pqrs*

# TOPCAT + STILTS (extra JAR with Parquet)
RUN curl -fsSL -o /usr/local/bin/topcat-extra.jar \
      https://www.star.bris.ac.uk/~mbt/topcat/topcat-extra.jar \
    && unzip -o /usr/local/bin/topcat-extra.jar -d /usr/local/bin topcat stilts \
    && sed -i -e 's/topcat-full/topcat-extra/g' /usr/local/bin/topcat /usr/local/bin/stilts \
    && chmod 644 /usr/local/bin/topcat-extra.jar \
    && chmod 755 /usr/local/bin/stilts /usr/local/bin/topcat

# Science Python (uv) — modern DIA via sfft / zogyp (not HOTPANTS)
COPY config/improc-py.txt /opt/astroai/improc-py.txt
RUN uv venv /opt/astroai/venv/improc \
    && uv pip install --python /opt/astroai/venv/improc -r /opt/astroai/improc-py.txt \
    && chmod -R a+rX /opt/astroai/venv/improc

# MaxiMask / MaxiTrack in an isolated TF venv — do not merge with improc.
# Only the CLIs are linked onto PATH (avoid shadowing science `python`).
COPY config/maximask-py.txt /opt/astroai/maximask-py.txt
RUN uv venv /opt/astroai/venv/maximask \
    && uv pip install --python /opt/astroai/venv/maximask -r /opt/astroai/maximask-py.txt \
    && ln -sf /opt/astroai/venv/maximask/bin/maximask /usr/local/bin/maximask \
    && ln -sf /opt/astroai/venv/maximask/bin/maxitrack /usr/local/bin/maxitrack \
    && chmod -R a+rX /opt/astroai/venv/maximask

# sourcextractor++ (astrorama channel)
ARG SOURCEXTRACTOR_VERSION
RUN micromamba create -y -p /opt/astroai/conda/sxpp \
      -c astrorama -c conda-forge \
      "sourcextractor=${SOURCEXTRACTOR_VERSION}" \
    && micromamba clean -a -y \
    && ln -sf /opt/astroai/conda/sxpp/bin/sourcextractor++ /usr/local/bin/sourcextractor++ \
    && ln -sf /opt/astroai/conda/sxpp/bin/sourcextractor++ /usr/local/bin/sourcextractor \
    && chmod -R a+rX /opt/astroai/conda/sxpp

COPY scripts/improc-profile.sh /etc/profile.d/improc.sh
COPY docs/USAGE.md /opt/astroai/USAGE.md
RUN chmod a+r /etc/profile.d/improc.sh /opt/astroai/USAGE.md

# Build-time smoke: required CLIs + Python imports
RUN set -euo pipefail; \
    . /etc/profile.d/improc.sh; \
    for c in \
      source-extractor sextractor swarp SWarp psfex scamp stiff missfits \
      fitscut fitspng fitsverify fpack funpack \
      weightwatcher montage theli \
      galfit imfit pqrs topcat stilts fits2idia imcore \
      astconvertt astnoisechisel astscript-psf-stamp \
      h5dump maximask maxitrack; do \
        command -v "$c" >/dev/null || { echo "MISSING: $c" >&2; exit 1; }; \
    done; \
    command -v sourcextractor++ >/dev/null \
      || command -v sourcextractor >/dev/null \
      || { echo "MISSING: sourcextractor++" >&2; exit 1; }; \
    scamp -v 2>&1 | head -1 | grep -q '2\.15' \
      || { echo "SCAMP not 2.15" >&2; exit 1; }; \
    /opt/astroai/venv/improc/bin/python -c "import ccdproc, photutils, galsim, piff, astroscrappy, lacosmic, sfft, zogyp, healpy, healsparse, astropy_healpix, mocpy, hpgeom"; \
    /opt/astroai/venv/maximask/bin/python -c "import tensorflow; import maximask_and_maxitrack"; \
    if /opt/astroai/venv/improc/bin/python -c "import tensorflow" 2>/dev/null; then \
      echo "FAIL: tensorflow leaked into improc venv" >&2; exit 1; \
    fi; \
    echo "improc smoke OK"

# syntax=docker/dockerfile:1
# Ray Manager — fat interactive base + Ray head + contributed UI (port 5000).

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG TAG=local

FROM ${REGISTRY}/${OWNER}/base:${TAG}

ARG TAG=local

LABEL io.canfar.skaha.session.type="contributed"
LABEL org.opencontainers.image.title="AstroAI Ray Manager" \
      org.opencontainers.image.version="${TAG}"

ENV RAY_IMAGE_TAG=${TAG}
ENV BUILD_TAG=${TAG}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY config/ray-deps.txt config/ray-deps.lock /tmp/
RUN uv python install 3.12 \
    && uv venv /opt/astroai/venv/ray --python 3.12 \
    && uv pip install --python /opt/astroai/venv/ray --requirements /tmp/ray-deps.lock \
    && rm /tmp/ray-deps.txt /tmp/ray-deps.lock \
    && /opt/astroai/venv/ray/bin/python -c "import ray; print(ray.__version__)" \
        > /opt/astroai/ray-version.txt \
    && chmod a+r /opt/astroai/ray-version.txt \
    && uv pip install --python /opt/astroai/venv/ray \
        canfar \
        fastapi uvicorn[standard] python-multipart httpx websockets

ENV PATH="/opt/astroai/venv/ray/bin:/opt/astroai/venv/cadc/bin:${PATH}"

COPY ray/worker/start-worker.sh /opt/astroai/bin/start-ray-worker.sh
COPY scripts/ray-head-start.sh /opt/astroai/bin/ray-head-start.sh
COPY scripts/ray-network-probe.sh /opt/astroai/bin/ray-network-probe.sh
COPY scripts/lib/ray-version.sh /opt/astroai/lib/ray-version.sh
COPY examples/ray/ /opt/astroai/examples/ray/
COPY ray/manager/ /opt/astroai/ray-manager/
COPY scripts/startup-ray-manager.sh /skaha/startup.sh
RUN chmod a+rx /opt/astroai/bin/start-ray-worker.sh /opt/astroai/bin/ray-head-start.sh \
    /opt/astroai/bin/ray-network-probe.sh /opt/astroai/lib/ray-version.sh \
    /skaha/startup.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/healthz >/dev/null

WORKDIR /tmp
CMD ["/skaha/startup.sh"]

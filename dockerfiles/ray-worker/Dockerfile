# syntax=docker/dockerfile:1
# Ray worker — headless CPU or GPU (CANFAR gpu=N at launch); joins manager via env contract.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG TAG=local

FROM ${REGISTRY}/${OWNER}/ray-base:${TAG}

LABEL io.canfar.skaha.session.type="headless"

ENTRYPOINT ["/opt/astroai/bin/start-ray-worker.sh"]

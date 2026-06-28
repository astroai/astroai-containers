# syntax=docker/dockerfile:1
# Ray CPU worker — headless; joins manager Ray head via env contract.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG TAG=local

FROM ${REGISTRY}/${OWNER}/ray-base:${TAG}

LABEL io.canfar.skaha.session.type="headless"

ENTRYPOINT ["/opt/astroai/bin/start-ray-worker.sh"]

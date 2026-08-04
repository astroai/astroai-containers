# AstroAI container stack — build with: docker buildx bake

variable "REGISTRY" {
  default = "images.canfar.net"
}

variable "OWNER" {
  default = "astroai"
}

variable "TAG" {
  default = "local"
}

variable "PYTHON_VERSION" {
  default = "3.13"
}

group "default" {
  targets = ["base", "webterm", "notebook", "vscode", "marimo", "openresearch", "openworker"]
}

group "improc" {
  targets = ["improc", "improc-webterm", "improc-notebook"]
}

target "python" {
  context    = "./dockerfiles/python"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/python:${PYTHON_VERSION}"]
  args = {
    PYTHON_VERSION = "${PYTHON_VERSION}"
  }
}

target "base" {
  context    = "."
  dockerfile = "dockerfiles/base/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/python:${PYTHON_VERSION}" = "target:python"
  }
  tags = ["${REGISTRY}/${OWNER}/base:${TAG}"]
  args = {
    REGISTRY       = "${REGISTRY}"
    OWNER          = "${OWNER}"
    PYTHON_VERSION = "${PYTHON_VERSION}"
  }
}

target "_interface" {
  context = "."
  contexts = {
    "${REGISTRY}/${OWNER}/base:${TAG}" = "target:base"
  }
  args = {
    REGISTRY  = "${REGISTRY}"
    OWNER     = "${OWNER}"
    BASE_NAME = "base"
    TAG       = "${TAG}"
  }
}

target "webterm" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/webterm/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/webterm:${TAG}"]
}

target "notebook" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/notebook/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/notebook:${TAG}"]
}

target "vscode" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/vscode/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/vscode:${TAG}"]
}

target "marimo" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/marimo/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/marimo:${TAG}"]
}

target "openresearch" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/openresearch/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/openresearch:${TAG}"]
  args = {
    # Ray Jobs backend — pin fork SHA until alphaXiv ships a release with
    # https://github.com/alphaXiv/openresearch-cli/pull/138
    ORX_REPO = "https://github.com/sfabbro/openresearch-cli.git"
    ORX_SHA  = "e076d027c9cbbac8b7bb5ded0821efa9d0a41c6b"
  }
}

target "openworker" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/openworker/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/openworker:${TAG}"]
  args = {
    OPENWORKER_SHA = "01b6f83b3927e02912dda84bb392942c13ca70d1"
  }
}

# Ray cluster images
# - ray-base: slim (from python) → ray-worker
# - ray-manager: fat (from base) + Ray runtime
target "ray-base" {
  context    = "."
  dockerfile = "dockerfiles/ray-base/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/python:${PYTHON_VERSION}" = "target:python"
  }
  tags = ["${REGISTRY}/${OWNER}/ray-base:${TAG}"]
  args = {
    REGISTRY       = "${REGISTRY}"
    OWNER          = "${OWNER}"
    PYTHON_VERSION = "${PYTHON_VERSION}"
    TAG            = "${TAG}"
  }
}

target "ray-worker" {
  context    = "."
  dockerfile = "dockerfiles/ray-worker/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/ray-base:${TAG}" = "target:ray-base"
  }
  tags = ["${REGISTRY}/${OWNER}/ray-worker:${TAG}"]
  args = {
    REGISTRY = "${REGISTRY}"
    OWNER    = "${OWNER}"
    TAG      = "${TAG}"
  }
}

target "ray-manager" {
  context    = "."
  dockerfile = "dockerfiles/ray-manager/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/base:${TAG}" = "target:base"
  }
  tags = ["${REGISTRY}/${OWNER}/ray-manager:${TAG}"]
  args = {
    REGISTRY = "${REGISTRY}"
    OWNER    = "${OWNER}"
    TAG      = "${TAG}"
  }
}

# Headless astronomy image-processing CLIs (FITS/HDF5). Not in default group.
target "improc" {
  context    = "."
  dockerfile = "dockerfiles/improc/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/base:${TAG}" = "target:base"
  }
  tags = ["${REGISTRY}/${OWNER}/improc:${TAG}"]
  args = {
    REGISTRY = "${REGISTRY}"
    OWNER    = "${OWNER}"
    TAG      = "${TAG}"
  }
}

# Interactive browser terminal on improc (reuses webterm Dockerfile, BASE_NAME=improc).
target "improc-webterm" {
  context    = "."
  dockerfile = "dockerfiles/webterm/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/improc:${TAG}" = "target:improc"
  }
  tags = ["${REGISTRY}/${OWNER}/improc-webterm:${TAG}"]
  args = {
    REGISTRY  = "${REGISTRY}"
    OWNER     = "${OWNER}"
    BASE_NAME = "improc"
    TAG       = "${TAG}"
  }
}

# JupyterLab on improc — default kernel is the science venv.
target "improc-notebook" {
  context    = "."
  dockerfile = "dockerfiles/improc-notebook/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/improc:${TAG}" = "target:improc"
  }
  tags = ["${REGISTRY}/${OWNER}/improc-notebook:${TAG}"]
  args = {
    REGISTRY  = "${REGISTRY}"
    OWNER     = "${OWNER}"
    BASE_NAME = "improc"
    TAG       = "${TAG}"
  }
}

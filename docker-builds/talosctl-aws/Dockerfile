# Multi-stage build: copy static talosctl binary into the AWS CLI image.
# Keep TALOS_VERSION in sync with the cluster version in terraform/versions.tf.
ARG TALOS_VERSION=v1.12.6

FROM ghcr.io/siderolabs/talosctl:${TALOS_VERSION} AS talosctl-src

FROM public.ecr.aws/aws-cli/aws-cli:latest

COPY --from=talosctl-src /talosctl /usr/local/bin/talosctl

# Smoke-test both CLIs at build time so a broken image fails fast.
RUN talosctl version --client && aws --version

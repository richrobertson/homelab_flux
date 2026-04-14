# Code-Server (Production)

Production overlay for code-server.

## Purpose

- Inherits base code-server configuration.
- Currently not exposed to the internet (no gateway/ingress configured).
- Accessible internally within the production cluster.

## In this folder

- Kustomization overlay that references the base code-server configuration.

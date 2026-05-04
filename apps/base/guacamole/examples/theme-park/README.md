# Theme Park Example

Theme Park dark mode for Guacamole is not applied by the active manifests because this repo uses Istio Gateway API rather than an ingress controller with response body injection.

If a future NGINX or Traefik proxy layer is added in front of Guacamole, apply the Theme Park Guacamole dark CSS through that proxy and keep it environment-specific. Do not modify Guacamole application assets in the container.


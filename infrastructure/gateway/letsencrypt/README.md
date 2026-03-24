# Gateway Let's Encrypt

Certificate automation resources used by gateway-exposed services.

## Purpose

- Manages ACME/certificate resources for TLS termination at the gateway layer.
- Keeps certificate issuance and renewal configuration version-controlled.

## In this folder

- Let's Encrypt issuer/challenge-related gateway integration manifests.

## Notes

- Coordinate DNS and gateway route updates when changing cert domains.


## Parent/Siblings

- Parent: [Gateway](../README.md)
- Siblings: [External Services](../externalServices/README.md); [myrobertson.com](../myrobertson-com/README.md).

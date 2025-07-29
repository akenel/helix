vault write auth/oidc/config \
  oidc_discovery_url="https://<keycloak-domain>/realms/<realm>" \
  oidc_client_id="<client-id>" \
  oidc_client_secret="<client-secret>" \
  default_role="default"
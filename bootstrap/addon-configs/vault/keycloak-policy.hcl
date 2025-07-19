# Vault policy to match Keycloak helix realm
path "secret/data/helix/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/oidc/login" {
  capabilities = ["create", "read"]
}

# Policies for realm-role specific access
path "secret/data/helix/admin/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "secret/data/helix/dev/*" {
  capabilities = ["create", "read", "update"]
}

path "secret/data/helix/test/*" {
  capabilities = ["read", "list"]
}

path "secret/data/helix/guest/*" {
  capabilities = ["read"]
}

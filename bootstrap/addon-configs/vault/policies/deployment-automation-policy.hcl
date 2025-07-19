# Admins get full access
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Devs can read and write in dev space
path "secret/data/dev/*" {
  capabilities = ["read", "create", "update", "list"]
}

# Testers can only read in test space
path "secret/data/test/*" {
  capabilities = ["read", "list"]
}

# Guests can only list public metadata
path "secret/metadata/public/*" {
  capabilities = ["read", "list"]
}
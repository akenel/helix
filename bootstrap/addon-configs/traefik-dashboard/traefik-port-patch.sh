kubectl -n kube-system patch svc traefik --type='merge' -p '{
  "spec": {
    "ports": [
      {
        "name": "web",
        "port": 80,
        "targetPort": 8000,
        "protocol": "TCP"
      },
      {
        "name": "websecure",
        "port": 443,
        "targetPort": 8443,
        "protocol": "TCP"
      },
      {
        "name": "dashboard",
        "port": 9000,
        "targetPort": 9000,
        "protocol": "TCP"
      }
    ]
  }
}'

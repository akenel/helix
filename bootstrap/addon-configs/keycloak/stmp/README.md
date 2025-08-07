helm install mailu mailu/mailu --version 2.2.2 --create-namespace --namespace mailu-system --values bootstrap/addon-configs/keycloak/stmp/deploy-keycloak-email.yaml

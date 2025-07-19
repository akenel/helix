
# install-portainer.sh
PLUGIN_NAME="Portainer"
PLUGIN_DESC="Web-based Docker & K8s dashboard"

run_plugin() {
  helm install portainer portainer/portainer \
    --namespace portainer --create-namespace \
    -f ../configs/portainer/portainer-values.yaml
}

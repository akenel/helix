#!/bin/sh
# install-nfs-client.sh - Script to install nfs-client in k3d nodes
echo "Updating apk repositories and installing nfs-client..."
apk update
apk add nfs-client
echo "nfs-client installation complete."
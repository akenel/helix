kubectl create namespace medusa
helm install medusa oci://registry-1.docker.io/alphayax/medusa --version 1.1.49 -n medusa

kubectl get pods -A 
NAMESPACE      NAME                     READY   STATUS              RESTARTS       AGE
medusa         medusa-5d7bf9955-qvs48   0/1     ContainerCreating   0              3m15s

kubectl port-forward svc/medusa 8080:8080
Then, access to http://localhost:8080

Example 
angel@LAPTOP-Q5JJGG0L:~/helix$ kubectl create namespace medusa
helm install medusa oci://registry-1.docker.io/alphayax/medusa --version 1.1.49 -n medusa
namespace/medusa created
Pulled: registry-1.docker.io/alphayax/medusa:1.1.49
Digest: sha256:f87348c2adba83be30d83405c2d9ef24b25fa73e1c70d1870edb1ed67ab74c8d
NAME: medusa
LAST DEPLOYED: Tue Jul 29 12:43:58 2025
NAMESPACE: medusa
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
.

    -= MEDUSA =-


  Ingress is DISABLED.
    Application can be accessed via port-forwarding:
      kubectl port-forward svc/medusa 8080:8080
      Then, access to http://localhost:8080

  Persistence:
  - config    : DISABLED
  - downloads : DISABLED
  - tvshows   : DISABLED

.
angel@LAPTOP-Q5JJGG0L:~/helix$
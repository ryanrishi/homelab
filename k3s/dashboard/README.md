dashboard
===

# Installation
```sh
$ k apply -f service-account.yml
$ k apply -f cluster-role.yml

# Install the kubernetes dashboard
$ helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
$ helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard

# create a secret for the service account
$ k apply -f secret.yml
$ kubectl get secret admin-user -n kubernetes-dashboard -o jsonpath={".data.token"} | base64 -d
```

# Access the dashboard
```sh
$ export POD_NAME=$(kubectl get pods -n kubernetes-dashboard -l "app.kubernetes.io/name=kubernetes-dashboard,app.kubernetes.io/instance=kubernetes-dashboard" -o jsonpath="{.items[0].metadata.name}")
$ kubectl -n kubernetes-dashboard port-forward $POD_NAME 8443:8443
# visit https://localhost:8443, choose "Token" authentication, and enter the base64 encoded token from above
```

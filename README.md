# dex-gangway-ldap
"KIND" quick setup for dex , gangway and ldap.



To create cluster

```bash
./kind-cluster.sh make
```

To delete cluster

```bash
./kind-cluster.sh delete
```

Dex and Gangway configuration template  is located at kind-cluster.sh 

```bash
readonly TANZU_AUTH_NAMESPACE=tanzu-system-auth
readonly KUBE_API=https://127.0.0.1:9643/

readonly DEX_HOST=dex.auth.app.local
readonly DEX_PORT=9480
readonly DEX_TOKEN_URL=http://dexsvc/token ## dexsvc refer to service name for dex

readonly STATIC_CLIENT_ID=tanzu ## can be any name
readonly STATIC_CLIENT_SECRET=tanzu-security ## can be any key
readonly STATIC_CLIENT_SECRET_ENCODED=`echo -n "$STATIC_CLIENT_SECRET" | base64`

readonly GANGWAY_HOST=gangway.auth.app.local
readonly GANGWAY_PORT=9480
readonly LDAP_HOST=ldapsvc
readonly LDAP_PORT=389
```

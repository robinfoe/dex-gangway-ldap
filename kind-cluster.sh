#! /usr/bin/env bash



set -o pipefail
set -o errexit
set -o nounset

readonly KIND=${KIND:-kind}
readonly KUBECTL=${KUBECTL:-kubectl}

readonly CLUSTERNAME=${CLUSTER:-dex-gangway-ldap}
readonly WAITTIME=${WAITTIME:-5m}

readonly HERE=$(cd $(dirname $0) && pwd)
readonly REPO=$(cd ${HERE}/asset && pwd)
readonly REPO_KUBE=$(cd ${REPO}/kubernetes && pwd)
readonly REPO_TEMPLATE=$(cd ${REPO}/template && pwd)




## YTT configurations
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


kind::cluster::exists() {
    ${KIND} get clusters | grep -q "$1"
}

kind::cluster::create() {
    ${KIND} create cluster \
        --name "${CLUSTERNAME}" \
        --wait "${WAITTIME}" \
        --config "${REPO}/kind-expose-port.yaml"
}


kind::cluster::generate::config(){

    ## Generate DEX connfig
    # ytt  -f ${REPO_KUBE}/template/dex --output-directory ${REPO_KUBE}/dex

    ytt -v namespace=$TANZU_AUTH_NAMESPACE \
        -v dex.host=$DEX_HOST \
        -v dex.port=$DEX_PORT \
        -v gangway.host=$GANGWAY_HOST \
        -v gangway.port=$GANGWAY_PORT \
        -v ldap.host=$LDAP_HOST \
        -v ldap.port=$LDAP_PORT \
        -v static.client.id=$STATIC_CLIENT_ID \
        -v static.client.secret=$STATIC_CLIENT_SECRET \
        -f ${REPO_TEMPLATE}/dex \
        --output-directory ${REPO_KUBE}/dex


    ## Generate Gangway Config
    ytt -v namespace=$TANZU_AUTH_NAMESPACE \
        -v kube.api=$KUBE_API \
        -v dex.host=$DEX_HOST \
        -v dex.port=$DEX_PORT \
        -v dex.tokenUrl=$DEX_TOKEN_URL \
        -v gangway.host=$GANGWAY_HOST \
        -v gangway.port=$GANGWAY_PORT \
        -v static.client.id=$STATIC_CLIENT_ID \
        -v static.client.encoded=$STATIC_CLIENT_SECRET_ENCODED \
        -f ${REPO_TEMPLATE}/gangway \
        --output-directory ${REPO_KUBE}/gangway



}

## Deploy contour
kind::cluster::deploy::contour(){

    ## deploy contour
    for y in ${REPO_KUBE}/contour/*.yaml ; do
        ${KUBECTL} apply -f <(sed 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' < "$y")
    done

    ## wait for pod to be ready 

    ${KUBECTL} wait --timeout="${WAITTIME}" -n projectcontour -l app=contour deployments --for=condition=Available
    ${KUBECTL} wait --timeout="${WAITTIME}" -n projectcontour -l app=envoy pods --for=condition=Ready

    # Install cert-manager.
    ${KUBECTL} apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.14.1/cert-manager.yaml
    ${KUBECTL} wait --timeout="${WAITTIME}" -n cert-manager -l app=cert-manager deployments --for=condition=Available
    ${KUBECTL} wait --timeout="${WAITTIME}" -n cert-manager -l app=cert-manager pods --for=condition=Ready
    ${KUBECTL} wait --timeout="${WAITTIME}" -n cert-manager -l app=webhook pods --for=condition=Ready

}


## Deploy dex 
kind::cluster::deploy::dex(){

    ## deploy dex
    for y in ${REPO_KUBE}/dex/*.yaml ; do
        ${KUBECTL} apply -f <(sed 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' < "$y")
    done

    ${KUBECTL} wait --timeout="${WAITTIME}" -n tanzu-system-auth -l app=dex deployments --for=condition=Available
    ${KUBECTL} wait --timeout="${WAITTIME}" -n tanzu-system-auth -l app=dex pods --for=condition=Ready


    ## deploy gangway
    ${KUBECTL} get secret dex-cert-tls -n tanzu-system-auth -o 'go-template={{ index .data `ca.crt` }}' | base64 -D >  ${REPO_KUBE}/gangway/dex-ca.crt
    ${KUBECTL} create cm dex-ca -n tanzu-system-auth --from-file=dex-ca.crt=${REPO_KUBE}/gangway/dex-ca.crt
    
    for y in ${REPO_KUBE}/gangway/*.yaml ; do
        ${KUBECTL} apply -f <(sed 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' < "$y")
    done

    ${KUBECTL} wait --timeout="${WAITTIME}" -n tanzu-system-auth -l app=gangway deployments --for=condition=Available
    ${KUBECTL} wait --timeout="${WAITTIME}" -n tanzu-system-auth -l app=gangway pods --for=condition=Ready
}

## Deploy ldap service
kind::cluster::deploy::ldap(){

    for y in ${REPO_KUBE}/ldap/*.yaml ; do
        ${KUBECTL} apply -f <(sed 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' < "$y")
    done

    ${KUBECTL} wait --timeout="${WAITTIME}" -n tanzu-system-auth -l app=ldap deployments --for=condition=Available
    ${KUBECTL} wait --timeout="${WAITTIME}" -n tanzu-system-auth -l app=ldap pods --for=condition=Ready
}


## Make cluster
function kind::cluster::make(){
    echo "creating kind cluster.... "

    if ! kind::cluster::exists "$CLUSTERNAME" ; then
        kind::cluster::create
    fi


    kind::cluster::generate::config
    kind::cluster::deploy::contour
    kind::cluster::deploy::dex
    kind::cluster::deploy::ldap
}


## Delete cluster
function kind::cluster::delete(){
    ${KIND} delete cluster --name=$CLUSTERNAME
}



command=$1
kind::cluster::$command
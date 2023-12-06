---
title: "VAULT / AUTH - JWT - OIDC: Public Key Validation (Kubernetes)"
description: "HashiCorp Vault Authentication JWT/OIDC Public Key Validtaion with Kubernetes"
---

# VAULT / AUTH - JWT - OIDC: Public Key Validation (Kubernetes)

"Before a client can interact with Vault, it must authenticate against an auth method to acquire a token. This token has policies attached so that the behavior of the client can be governed."

[![High Level Flow - Auth Method](assets/vault-auth-idp-workflow.20231206.png)](https://developer.hashicorp.com/vault/docs/auth/jwt)

https://developer.hashicorp.com/vault/docs/auth/jwt

This method can be useful if Kubernetes' API is not reachable from Vault or if you would like a single JWT auth mount to service multiple Kubernetes clusters by chaining their public signing keys.

## PREREQUISITES

   - Docker
   - Kubernetes (K3s / K3d)
   - K8s [ServiceAccountIssuerDiscovery](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#service-account-issuer-discovery) feature enabled
   - kubectl
   - Vault CLI
   - Terraform
   - make
   - npm
   - pem-jwk (```npm install -g pem-jwk```)
   - jq
   - curl
   - openssl
   - PGP/GPG/PASS
   - Vault **[Initialized & Unsealed](https://learn.hashicorp.com/tutorials/vault/getting-started-deploy)**

## Versions

###### Docker Version

```shell
❯ docker version
Client:
 Cloud integration: v1.0.35-desktop+001
 Version:           24.0.5
 API version:       1.43
 Go version:        go1.20.6
 Git commit:        ced0996
 Built:             Fri Jul 21 20:32:30 2023
 OS/Arch:           darwin/arm64
 Context:           desktop-linux

Server: Docker Desktop 4.22.1 (118664)
 Engine:
  Version:          24.0.5
  API version:      1.43 (minimum version 1.12)
  Go version:       go1.20.6
  Git commit:       a61e2b4
  Built:            Fri Jul 21 20:35:38 2023
  OS/Arch:          linux/arm64
  Experimental:     false
 containerd:
  Version:          1.6.21
  GitCommit:        3dce8eb055cbb6872793272b4f20ed16117344f8
 runc:
  Version:          1.1.7
  GitCommit:        v1.1.7-0-g860f061
 docker-init:
  Version:          0.19.0
  GitCommit:        de40ad0
```

###### K3d / K3s Version

```shell
❯ k3d version
v5.6.0
k3s version v1.27.4-k3s1 (default)
```

###### Helm Version

```shell
❯ helm version
version.BuildInfo{Version:"v3.13.2", GitCommit:"2a2fb3b98829f1e0be6fb18af2f6599e0f4e8243", GitTreeState:"clean", GoVersion:"go1.21.4"}
```

###### Vault Version

```shell
❯ vault version
Vault v1.15.3 (25a4d1a00dc81a5b4907c76c2358f38d30c05747), built 2023-11-22T20:59:54Z
```

## Spin up a Kubernetes Cluster

Via **Terraform**:

https://github.com/F0otsh0T/hcp-vault-docker/tree/main/01-k3d

Manually via **Shell**:

```shell
k3d cluster create --agents 2 --k3s-arg "--tls-san=192.168.65.2"@server:* auth-jwt-pki
```
```192.168.65.2``` is ```host.docker.internal``` (and ```host.k3d.internal``` in our environment with **K3d**) with an overlay ```IP``` for host node ```127.0.0.1``` or ```0.0.0.0```

## Create K8s Resources
- Create a ```serviceaccount```

    Create a Kubernetes **serviceaccount** named ```vault-auth``` with **YAML Manifest** `vault-auth-k8s-clusterrolebinding.yaml`
    ```YAML
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: vault-auth
      namespace: default
    ```
    Create `serviceaccount`:

    ```shell
    kubectl create -f vault-auth-k8s-serviceaccount.yaml
    serviceaccount/vault-auth created
    ```

- Define ```clusterrolebinding```

    Create a Kubernetes **clusterrolebinding** resource with **clusterrole** of ```system:auth-delegator``` so that it applies that spec to the client of Vault (via **serviceaccount** <= **clusterrolebinding** <= **clusterrole**).

    Use the following **YAML manifest** as an example to create the **clusterrolebinding** resource with filename == `vault-auth-k8s-clusterrolebinding.yaml`:

    ```YAML
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: role-tokenreview-binding
      namespace: default
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: system:auth-delegator
    subjects:
    - kind: ServiceAccount
      name: vault-auth
      namespace: default
    ```

- Apply ```clusterrolebinding``` manifest to update the ```vault-auth``` ```serviceaccount```

    ```shell
    kubectl create -f vault-auth-k8s-clusterrolebinding.yaml
    clusterrolebinding.rbac.authorization.k8s.io/role-tokenreview-binding created
    ```

## Configuration Steps

1. Fetch the service account signing public key from your cluster's JWKS URI.
   > Note: This requirement can be avoided if you can access the Kubernetes master nodes to read the public signing key directly from disk at /etc/kubernetes/pki/sa.pub. In this case, you can skip the steps to retrieve and then convert the key as it will already be in PEM format.
    - Find the ```issuer``` URL for the Kubernetes Cluster
      ```shell
      export ISSUER="$(kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer')"

      echo $ISSUER
      https://kubernetes.default.svc.cluster.local
      ```
    - Query the jwks_uri specified in /.well-known/openid-configuration
      ```shell
      kubectl get --raw "$(kubectl get --raw /.well-known/openid-configuration | jq -r '.jwks_uri' | sed -r 's/.*\.[^/]+(.*)/\1/')" | jq -r '.keys[]'
      {
      "use": "sig",
      "kty": "RSA",
      "kid": "-IeWPXFbKw-sNfOX18TuIzLr6fr2sXjWEbU-okW7fz4",
      "alg": "RS256",
      "n": "LoremipsumdolorsitametconsecteturadipiscingelitExpectoquequidadidquodquaerebamrespondeasProfectusinexiliumTubulusstatimnecrespondereaususDuoRegesconstructiointerreteHicnihilfuitquodquaereremusSedilleutdixivitioseNonautemhocigiturneilludquidemAgeinquiesistaparvasuntQuemTiberinadescensiofestoillodietantogaudioaffecitquantoLSemperenimitaadsumitaliquiduteaquaeprimadederitnondeseratQuarumambarumrerumcummedicinampolliceturluxu",
      "e": "AQAB"
      }
      ```
2. Convert the keys from JWK format to PEM. You can use a CLI tool or an online converter such as **[this one](https://8gwifi.org/jwkconvertfunctions.jsp)**.
3. Enable and configure JWT auth in **Vault**
   ```shell
   vault auth enable jwt
   Success! Enabled jwt auth method at: jwt/
   ```
4. Configure the **JWT** Auth mount with those public keys.
   ```shell
   vault write auth/jwt/config \
      jwt_validation_pubkeys="-----BEGIN PUBLIC KEY-----
   LoremipsumdolorsitametconsecteturadipiscingelitExpectoquequidadid
   quodquaerebamrespondeasProfectusinexiliumTubulusstatimnecresponde
   reaususDuoRegesconstructiointerreteHicnihilfuitquodquaereremusSed
   illeutdixivitioseNonautemhocigiturneilludquidemAgeinquiesistaparv
   asuntQuemTiberinadescensiofestoillodietantogaudioaffecitquantoLSe
   mperenimitaadsumitaliquiduteaquaeprimadederitnondeseratQuarumamba
   rumrerum
   -----END PUBLIC KEY-----"
   Success! Data written to: auth/jwt/config

   vault read auth/jwt/config
   Key                       Value
   ---                       -----
   bound_issuer              n/a
   default_role              n/a
   jwks_ca_pem               n/a
   jwks_url                  n/a
   jwt_supported_algs        []
   jwt_validation_pubkeys    [-----BEGIN PUBLIC KEY-----
   LoremipsumdolorsitametconsecteturadipiscingelitExpectoquequidadid
   quodquaerebamrespondeasProfectusinexiliumTubulusstatimnecresponde
   reaususDuoRegesconstructiointerreteHicnihilfuitquodquaereremusSed
   illeutdixivitioseNonautemhocigiturneilludquidemAgeinquiesistaparv
   asuntQuemTiberinadescensiofestoillodietantogaudioaffecitquantoLSe
   mperenimitaadsumitaliquiduteaquaeprimadederitnondeseratQuarumamba
   rumrerum
   -----END PUBLIC KEY-----]
   namespace_in_state        true
   oidc_client_id            n/a
   oidc_discovery_ca_pem     n/a
   oidc_discovery_url        n/a
   oidc_response_mode        n/a
   oidc_response_types       []
   provider_config           map[]
   ```
5. Set Vault Policy
   - Will re-use this policy later in the excercise
   - For now, reference the `p.global.crudl.hcl` (Note: this policy has elevated privileges) or some other policy set with enough permissions to complete these steps
    ```shell
    $ vault policy write global.crudl p.global.crudl.hcl
    ```
6. ^^ **JWT** Auth mount is configured. Ready to configure a role.
   ```shell
   vault write auth/jwt/role/my-role \
      role_type="jwt" \
      bound_audiences="${ISSUER}" \
      user_claim="sub" \
      bound_subject="system:serviceaccount:default:vault-auth" \
      policies="global.crudl" \
      ttl="1h"

   vault read auth/jwt/role/my-role
   Key                        Value
   ---                        -----
   allowed_redirect_uris      <nil>
   bound_audiences            [https://kubernetes.default.svc.cluster.local]
   bound_claims               <nil>
   bound_claims_type          string
   bound_subject              system:serviceaccount:default:default
   claim_mappings             <nil>
   clock_skew_leeway          0
   expiration_leeway          0
   groups_claim               n/a
   max_age                    0
   not_before_leeway          0
   oidc_scopes                <nil>
   policies                   [default]
   role_type                  jwt
   token_bound_cidrs          []
   token_explicit_max_ttl     0s
   token_max_ttl              0s
   token_no_default_policy    false
   token_num_uses             0
   token_period               0s
   token_policies             [global.crudl]
   token_ttl                  1h
   token_type                 default
   ttl                        1h
   user_claim                 sub
   verbose_oidc_logging       false
   ```
7. Log in via **JWT** Auth Method Role to retrieve access **token**
    - Create ***test-oidc-jwt*** K8s ```deployment``` 
      ```shell
      ❯ kubectl create -f deploy.oidc-jwt.yaml
      deployment.apps/test-oidc-jwt created
      ```
    - Exec into the Pod and attempt to Log into **Vault** via ```curl```
      ```shell
      kubectl exec -it deployments/test-oidc-jwt -- bash

      export VAULT_ADDR=http://192.168.65.2:8200

      export JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

      curl \
         --fail \
         --request POST \
         --header "X-Vault-Request: true" \
         --data '{"jwt":"'"${JWT}"'","role":"my-role"}' \
         "${VAULT_ADDR}/v1/auth/jwt/login"
      {
      "request_id": "129e8219-f7da-56fc-12f5-15eea3d36acutlb6",
      "lease_id": "",
      "renewable": false,
      "lease_duration": 0,
      "data": null,
      "wrap_info": null,
      "warnings": null,
      "auth": {
         "client_token": "s.Loremipsumdolorsitametco",
         "accessor": "Loremipsumdolorsitametco",
         "policies": [
            "default"
         ],
         "token_policies": [
            "default"
         ],
         "metadata": {
            "role": "my-role"
         },
         "lease_duration": 3600,
         "renewable": true,
         "entity_id": "87f06d06-b560-fb3d-0d77-3b40fe0431d7",
         "token_type": "service",
         "orphan": true
      }
      }

      ```

      ^^ ```client_token``` aquired

    - Alternatively if you have **Vault** CLI installed:
      ```shell
      vault write auth/jwt/login \
      role=my-role \
      jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
      ```



## Reference
- https://www.vaultproject.io/docs/auth/jwt
- https://www.vaultproject.io/docs/auth/jwt/oidc_providers#using-jwt-validation-public-keys
-  https://learn.hashicorp.com/tutorials/vault/agent-kubernetes#create-a-service-account
- https://www.vaultproject.io/docs/platform/k8s/injector
- https://learn.hashicorp.com/tutorials/vault/kubernetes-sidecar

## Appendix

###### JWK Conversion

- https://www.npmjs.com/package/pem-jwk
- https://github.com/dannycoates/pem-jwk
- https://8gwifi.org/jwkconvertfunctions.jsp

"`BEGIN RSA PUBLIC KEY`" is **PKCS#1**, which can only contain RSA keys.
"`BEGIN PUBLIC KEY`" is **PKCS#8**, which can contain a variety of formats.

To convert from **PKCS#8** to **PKCS#1:**

```
openssl rsa -pubin -in <filename> -RSAPublicKey_out
```

To convert from **PKCS#1** to **PKCS#8**:

```
openssl rsa -RSAPublicKey_in -in <filename> -pubout
```


###### kubernetes-k3s-certs-keys

**Kubernetes** `serviceaccount` certs are typically stored at `/etc/kubernetes/pki/sa.key` (*private key*)* & `/etc/kubernetes/pki/sa.pub` (*public key*.  However, **K3s** stores just the *private key* @ `/var/lib/rancher/k3s/server/tls/service.key` and you have to derive the *public key* via:

```shell
❯ openssl rsa -in /var/lib/rancher/k3s/server/tls/service.key -pubout > sa.pub
```

###### API
```shell
curl \
   --fail \
   --request POST \
   --header "X-Vault-Request: true" \
   --data "{\"jwt\":\"$(cat /var/run/secrets/kubernetes.io/serviceaccount/token )\",\"role\":\"my-role\"}" \
   "${VAULT_ADDR}/v1/auth/jwt/login"
```

```shell
curl \
   --fail \
   --request POST \
   --header "X-Vault-Request: true" \
   --data "{\"jwt\":\"${JWT}\",\"role\":\"my-role\"}" \
   "${VAULT_ADDR}/v1/auth/jwt/login"
```

JSON Body
```json
{
    "jwt":"$JWT",
    "role":"my-role"
}
```

CURL Request
```shell
curl \
   --fail \
   --request POST \
   --header "X-Vault-Request: true" \
   --data @body \
   "${VAULT_ADDR}/v1/auth/jwt/login"
```

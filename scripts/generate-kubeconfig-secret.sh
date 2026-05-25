#!/usr/bin/env bash
# Genera kubeconfig per GitHub Actions (secret KUBE_CONFIG_QA / KUBE_CONFIG_PROD).
# Uso: ./generate-kubeconfig-secret.sh business-qa <TOKEN> [admin.conf]
set -euo pipefail

NS="${1:?namespace es. business-qa}"
TOKEN="${2:?token da: kubectl create token github-actions-${NS} -n ${NS} --duration=8760h}"
ADMIN_CONF="${3:-${KUBECONFIG:-$HOME/.kube/config}}"

if [ ! -f "$ADMIN_CONF" ]; then
  echo "ERRORE: kubeconfig admin non trovato: $ADMIN_CONF" >&2
  exit 1
fi

if [ -z "$TOKEN" ] || [ "${#TOKEN}" -lt 20 ]; then
  echo "ERRORE: TOKEN non valido (troppo corto o vuoto)" >&2
  exit 1
fi

SA="github-actions-${NS}"
SERVER=$(kubectl --kubeconfig="$ADMIN_CONF" config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl --kubeconfig="$ADMIN_CONF" config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

if [ -z "$SERVER" ]; then
  echo "ERRORE: impossibile leggere server dal kubeconfig admin" >&2
  exit 1
fi

if [ -z "$CA_DATA" ]; then
  echo "ERRORE: certificate-authority-data mancante in $ADMIN_CONF" >&2
  exit 1
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# IMPORTANTE: token va sotto "user:", non come sibling di "name:"
cat >"$TMP" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: cluster
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}
contexts:
  - name: ${SA}@${NS}
    context:
      cluster: cluster
      namespace: ${NS}
      user: ${SA}
current-context: ${SA}@${NS}
users:
  - name: ${SA}
    user:
      token: ${TOKEN}
EOF

# Verifica locale (solo permessi nel namespace, non kube-system)
export KUBECONFIG="$TMP"
kubectl config current-context >/dev/null
kubectl auth can-i get deployments -n "$NS" | grep -q '^yes$'
kubectl auth can-i patch deployments -n "$NS" | grep -q '^yes$'

ENV_SUFFIX=$(echo "${NS#business-}" | tr '[:lower:]' '[:upper:]')
echo "# Secret GitHub: KUBE_CONFIG_${ENV_SUFFIX}" >&2
echo "# Namespace: ${NS} | ServiceAccount: ${SA}" >&2
echo "# Incolla SOLO la riga base64 qui sotto nel secret GitHub" >&2
base64 <"$TMP" | tr -d '\n'
echo

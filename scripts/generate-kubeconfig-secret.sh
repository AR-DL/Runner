#!/usr/bin/env bash
# Genera kubeconfig per GitHub Actions (secret KUBE_CONFIG_QA / KUBE_CONFIG_PROD).
# Uso: ./generate-kubeconfig-secret.sh mng-qa <TOKEN> [admin.conf]
set -euo pipefail

NS="${1:?namespace es. mng-qa}"
TOKEN="${2:?token da: kubectl create token github-actions-${NS} -n ${NS}}"
ADMIN_CONF="${3:-/Users/davidelavalle/Desktop/kubernetees/admin.conf}"

SA="github-actions-${NS}"
SERVER=$(grep 'server:' "$ADMIN_CONF" | awk '{print $2}')
CA_DATA=$(grep 'certificate-authority-data:' "$ADMIN_CONF" | awk '{print $2}')

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

cat >"$TMP" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: kubeadm
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}
contexts:
  - name: ${SA}@${NS}
    context:
      cluster: kubeadm
      namespace: ${NS}
      user: ${SA}
current-context: ${SA}@${NS}
users:
  - name: ${SA}
    token: ${TOKEN}
EOF

ENV_SUFFIX=$(echo "${NS#mng-}" | tr '[:lower:]' '[:upper:]')
echo "# Secret GitHub: KUBE_CONFIG_${ENV_SUFFIX}"
echo "# Namespace: ${NS} | ServiceAccount: ${SA}"
base64 <"$TMP" | tr -d '\n'
echo

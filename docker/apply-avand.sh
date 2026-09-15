#!/usr/bin/env bash
# Applies the Avand/Bee (StorageService) objects — and the deltas that arrived with
# newest-realm-export.json — to the LIVE identity-service realm. The realm already exists, so
# `--import-realm` skips realm-export.json; this script is the live-side counterpart and is safe
# to re-run (create-if-missing / update-in-place throughout).
#
# Run from the host:  bash apply-avand.sh
# (it re-executes itself inside the shared-keycloak container, where kcadm.sh and the
#  KC_*_CLIENT_SECRET / KC_BOOTSTRAP_ADMIN_* environment variables live).
set -euo pipefail

if [ ! -x /opt/keycloak/bin/kcadm.sh ]; then
  exec docker exec -i shared-keycloak bash -s -- <"$0"
fi

KCADM=/opt/keycloak/bin/kcadm.sh
REALM=identity-service

$KCADM config credentials --server http://localhost:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD"

client_id() { $KCADM get clients -r "$REALM" -q "clientId=$1" --fields id --format csv --noquotes | head -1 || true; }
scope_id()  { $KCADM get client-scopes -r "$REALM" --fields id,name --format csv --noquotes | grep ",$1\$" | cut -d, -f1 | head -1 || true; }

# --- realm: allow forgot-password, mail via shared mailpit (swap for real SMTP before production)
$KCADM update "realms/$REALM" -s resetPasswordAllowed=true \
  -s 'smtpServer={"host":"mailpit","port":"1025","from":"no-reply@shokoofa.ai","auth":"","ssl":"","starttls":""}'

# --- client scope: bee-api-audience (aud=bee-api in avand-web access tokens)
AUD_ID=$(scope_id bee-api-audience)
if [ -z "$AUD_ID" ]; then
  AUD_ID=$($KCADM create client-scopes -r "$REALM" -i -f - <<'JSON'
{"name":"bee-api-audience","description":"Adds bee-api to the aud claim of access tokens",
 "protocol":"openid-connect",
 "attributes":{"include.in.token.scope":"false","display.on.consent.screen":"false"},
 "protocolMappers":[{"name":"bee-api-audience","protocol":"openid-connect",
   "protocolMapper":"oidc-audience-mapper","consentRequired":false,
   "config":{"included.client.audience":"bee-api","id.token.claim":"false",
             "access.token.claim":"true","introspection.token.claim":"true"}}]}
JSON
  )
  echo "created client scope bee-api-audience ($AUD_ID)"
fi

# --- client scope: AuthnContextClassRef (from newest-realm-export.json)
if [ -z "$(scope_id AuthnContextClassRef)" ]; then
  $KCADM create client-scopes -r "$REALM" -f - <<'JSON'
{"name":"AuthnContextClassRef","description":"AuthnContextClassRef Level of Authentiation",
 "protocol":"saml","attributes":{},
 "protocolMappers":[{"name":"AuthnContextClassRef","protocol":"saml",
   "protocolMapper":"saml-authn-context-class-ref-mapper","consentRequired":false,"config":{}}]}
JSON
  echo "created client scope AuthnContextClassRef"
fi

# --- client: bee-api (bearer-only resource server carrying the app roles)
BEE_API_ID=$(client_id bee-api)
if [ -z "$BEE_API_ID" ]; then
  BEE_API_ID=$($KCADM create clients -r "$REALM" -i -f - <<'JSON'
{"clientId":"bee-api","name":"Bee API","enabled":true,"protocol":"openid-connect",
 "description":"Bee storage API - bearer-only resource server; carries the Avand app roles",
 "publicClient":false,"bearerOnly":true,"standardFlowEnabled":false,"implicitFlowEnabled":false,
 "directAccessGrantsEnabled":false,"serviceAccountsEnabled":false,
 "redirectUris":[],"webOrigins":[],"defaultClientScopes":[],"optionalClientScopes":[]}
JSON
  )
  echo "created client bee-api ($BEE_API_ID)"
fi
for pair in "Admin|Full control (bee:admin)" "Operator|Write, purge, stream (bee:write/purge/stream)" "Viewer|Read-only (bee:read)"; do
  role="${pair%%|*}"; desc="${pair#*|}"
  if ! $KCADM get "clients/$BEE_API_ID/roles/$role" -r "$REALM" >/dev/null 2>&1; then
    $KCADM create "clients/$BEE_API_ID/roles" -r "$REALM" -s "name=$role" -s "description=$desc"
    echo "created bee-api role $role"
  fi
done

# --- client: avand-web (Avand BFF, authorization code + PKCE)
AVAND_JSON=$(cat <<JSON
{"clientId":"avand-web","name":"Avand front end","enabled":true,"protocol":"openid-connect",
 "description":"Avand (Bee storage) Next.js BFF - authorization code + PKCE",
 "publicClient":false,"standardFlowEnabled":true,"implicitFlowEnabled":false,
 "directAccessGrantsEnabled":false,"serviceAccountsEnabled":false,
 "clientAuthenticatorType":"client-secret","secret":"$KC_AVAND_CLIENT_SECRET",
 "redirectUris":["https://avand.shokoofa.ai/api/auth/callback","http://localhost:22030/api/auth/callback","http://localhost:3000/api/auth/callback"],
 "webOrigins":["https://avand.shokoofa.ai","http://localhost:22030","http://localhost:3000"],
 "attributes":{"pkce.code.challenge.method":"S256",
   "post.logout.redirect.uris":"https://avand.shokoofa.ai##http://localhost:22030##http://localhost:3000"}}
JSON
)
AVAND_ID=$(client_id avand-web)
if [ -z "$AVAND_ID" ]; then
  AVAND_ID=$(echo "$AVAND_JSON" | $KCADM create clients -r "$REALM" -i -f -)
  echo "created client avand-web ($AVAND_ID)"
else
  echo "$AVAND_JSON" | $KCADM update "clients/$AVAND_ID" -r "$REALM" -f -
  echo "updated client avand-web"
fi
$KCADM update "clients/$AVAND_ID/default-client-scopes/$AUD_ID" -r "$REALM"

# --- client: bee-admin (service account for Bee's role-assignment proxy)
BEE_ADMIN_JSON=$(cat <<JSON
{"clientId":"bee-admin","name":"Bee admin service account","enabled":true,"protocol":"openid-connect",
 "description":"Service account Bee uses to manage bee-api role assignments",
 "publicClient":false,"standardFlowEnabled":false,"implicitFlowEnabled":false,
 "directAccessGrantsEnabled":false,"serviceAccountsEnabled":true,
 "clientAuthenticatorType":"client-secret","secret":"$KC_BEE_ADMIN_CLIENT_SECRET",
 "redirectUris":[],"webOrigins":[]}
JSON
)
BEE_ADMIN_ID=$(client_id bee-admin)
if [ -z "$BEE_ADMIN_ID" ]; then
  BEE_ADMIN_ID=$(echo "$BEE_ADMIN_JSON" | $KCADM create clients -r "$REALM" -i -f -)
  echo "created client bee-admin ($BEE_ADMIN_ID)"
else
  echo "$BEE_ADMIN_JSON" | $KCADM update "clients/$BEE_ADMIN_ID" -r "$REALM" -f -
  echo "updated client bee-admin"
fi
$KCADM add-roles -r "$REALM" --uusername service-account-bee-admin \
  --cclientid realm-management --rolename manage-users --rolename view-users

# --- scrumkanban-web: ADD the production redirect from newest-realm-export.json without
#     dropping the localhost URIs the locally-run stack still uses.
SK_ID=$(client_id scrumkanban-web)
if [ -n "$SK_ID" ]; then
  # union of the local-dev URIs (old export) and the production ones (newest export)
  $KCADM update "clients/$SK_ID" -r "$REALM" \
    -s 'redirectUris=["http://localhost:3000/api/auth/callback","https://plan.shokoofa.ai/api/auth/callback"]' \
    -s 'webOrigins=["http://localhost:3000","https://plan.shokoofa.ai"]'
  echo "scrumkanban-web redirect/webOrigin union applied"
fi

echo "apply-avand.sh: done."

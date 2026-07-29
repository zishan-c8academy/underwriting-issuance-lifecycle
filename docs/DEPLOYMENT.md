# Deployment guide (SaaS, Camunda 8 Run, Docker Compose, Self-Managed)

The `bpmn/`, `dmn/` and `forms/` files deploy **unchanged** to every Camunda 8 flavour. This example has
no worker process, no connector and no secrets, so moving between targets only changes where you deploy
and how you authenticate.

**Verified:** this example has been run end to end on **Camunda 8 SaaS**. The full lifecycle deployed
(4 processes, 1 DMN, 13 forms), every human step completed through the API, the DMN routed correctly,
the crediting-participant Pending loop re-created its task, the client-response message correlated on
the CUSIP across two call activities, the parallel correction produced both tasks, the overdue timer
fired a supervisor escalation without cancelling the original task, and the instance reached COMPLETED.

## The matrix

| Target | Deploy with | Auth | Best for |
|--------|-------------|------|----------|
| **SaaS** (incl. the free trial) | Web Modeler, or Desktop Modeler with cluster credentials | OAuth client credentials from Console | fastest start, nothing to install, shareable with colleagues |
| **Camunda 8 Run** | Desktop Modeler to `localhost` | basic auth, `demo:demo` by default | a laptop, offline, zero setup |
| **Docker Compose** (Self-Managed) | Modeler or API to `localhost` | as configured in the compose file | a local stack closer to production |
| **Self-Managed** (Kubernetes / Helm) | Modeler with a port-forward, or CI | your identity provider | production, or a cluster inside your network |

## SaaS (including the trial)

1. Create a cluster in Camunda Console (the trial is enough for this example).
2. Deploy in one of two ways:
   - **Web Modeler:** create a project, upload the 4 BPMN, the DMN and the 13 forms, then deploy.
   - **Desktop Modeler:** create an API client in Console (scope: **Orchestration Cluster REST API**),
     then deploy with the cluster id, region, client id and client secret.
3. Open Tasklist and Operate from Console and work the queues exactly as in the README.

To publish the client-response message on SaaS, get a token for your API client and call
`POST /v2/messages/publication` on the cluster's REST endpoint, the same call
`scripts/simulate-client-response.sh` makes locally:

```bash
# 1. token
TOKEN=$(curl -s -X POST https://login.cloud.camunda.io/oauth/token \
  -H 'Content-Type: application/json' \
  -d '{"grant_type":"client_credentials","audience":"zeebe.camunda.io",
       "client_id":"'"$CLIENT_ID"'","client_secret":"'"$CLIENT_SECRET"'"}' | jq -r .access_token)

# 2. publish, correlating on the CUSIP you entered
curl -s -X POST "https://$REGION.zeebe.camunda.io/$CLUSTER_ID/v2/messages/publication" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"ClientSecurityAttributesReturned","correlationKey":"123456789","timeToLive":180000,
       "variables":{"clientFirstPaymentDate":"2027-03-15","clientMaturityDate":"2032-09-15",
                    "clientInterestRate":4.25,"clientPaymentFrequency":"SEMI_ANNUAL"}}'
```

## Camunda 8 Run (local)

```bash
./start.sh        # Windows: start.bat
```
Deploy all 18 resources from Desktop Modeler, then start `UnderwritingIssuance`. The helper script
defaults to `http://localhost:8080` with `demo:demo`.

## Docker Compose (Self-Managed)

Use the official `camunda/camunda-platform` compose file, deploy the same way, and point the script at
the right host:

```bash
C8_REST_BASE=http://localhost:8080 ./scripts/simulate-client-response.sh 123456789
```

## Self-Managed on Kubernetes (Helm)

Deploy to the in-cluster gateway (Modeler over a port-forward, or `zbctl` / the REST API from CI).
Publish the client message with `POST /v2/messages/publication` against the gateway, using a token from
your identity provider.

## Keeping integrations inside your network, even on SaaS

This example has no connectors or workers today, so nothing needs network access to your systems. That
changes the moment you follow the README's connector table (replacing a human step with an Email or
REST connector) or add a job worker. Two facts worth knowing, because they decide whether SaaS is
viable for an internal system:

**Job workers always run wherever you put them.** A worker opens an **outbound** connection to the
gateway and polls for jobs. Nothing needs to be exposed inbound. So a worker running in your own
datacenter can serve a SaaS cluster and reach internal systems directly. This is the normal way to keep
custom integration logic inside your network.

**Connectors normally execute in a Camunda-hosted runtime on SaaS**, which cannot see a system behind
your firewall. The supported answer is **hybrid mode**: run the Camunda **connector runtime yourself,
inside your network**, attached to your SaaS cluster. The connector then executes on your side and
reaches internal systems directly, while orchestration stays in SaaS.

Hybrid mode in outline (see the Camunda docs for the current, complete list):

- Requires the connector runtime **0.23.0 or later**.
- Create an API client in Console with the **Orchestration Cluster REST API** scope, then point the
  runtime at the cluster:
  ```
  CAMUNDA_CLIENT_MODE=saas
  CAMUNDA_CLIENT_CLOUD_CLUSTERID=<cluster id>
  CAMUNDA_CLIENT_CLOUD_REGION=<region>
  CAMUNDA_CLIENT_AUTH_CLIENTID=<client id>
  CAMUNDA_CLIENT_AUTH_CLIENTSECRET=<client secret>
  ```
- Each connector you want handled locally is overridden to its local type, of the form
  `CONNECTOR_<NAME>_TYPE=io.camunda:<connector>:local`, and the element template in the model is
  adjusted to reference that local type. This is the main thing to plan for: the type value differs
  between the hosted and local runtime.
- To keep using **Console-managed connector secrets** from the local runtime, add the **Secrets** scope
  to the API client and set `CAMUNDA_CONNECTOR_SECRETPROVIDER_CONSOLE_ENABLED=true`.

Reference: [Use connectors in hybrid mode](https://docs.camunda.io/docs/guides/use-connectors-in-hybrid-mode/).

On **Camunda 8 Run, Docker Compose and Self-Managed** this question does not arise: the connector
runtime is already yours and already inside your network.

## Reference bindings

Forms, the DMN and the called processes are referenced with `bindingType="latest"`, which is forgiving
while you iterate: deploy files in any order, update one form without redeploying the process. For
production, switch to `bindingType="deployment"` (or a `versionTag`) so each process version pins the
exact form and decision versions it was tested with, and deploy all resources together.

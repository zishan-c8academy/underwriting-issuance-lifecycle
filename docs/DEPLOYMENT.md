# Deployment guide (C8 Run, Docker Compose, Self-Managed, SaaS)

The `bpmn/`, `dmn/` and `forms/` files deploy **unchanged** to every Camunda 8 flavour. This example
has no worker process, no connector and no secrets, so moving between targets only changes where you
deploy and how you reach Tasklist and Operate.

## The matrix

| Target | Deploy with | Tasklist / Operate at | Publish the client message via | Notes |
|--------|-------------|-----------------------|-------------------------------|-------|
| **Camunda 8 Run** (quickstart) | Desktop Modeler to `localhost` | `http://localhost:8080` | `scripts/simulate-client-response.sh` | Simplest. Nothing else to install. |
| **Docker Compose** (Self-Managed) | Modeler or API to `localhost` | `http://localhost:8080` (Tasklist), `:8081` (Operate) by default | same script, adjust `C8_REST_BASE` | Use the official `camunda/camunda-platform` compose file. |
| **Self-Managed** (Kubernetes / Helm) | Modeler with a port-forward, or CI | your ingress hostnames | the same REST call against the gateway | Auth via your identity provider. |
| **SaaS** | Web or Desktop Modeler to the cluster | your cluster's Tasklist / Operate URLs | the same REST call against the cluster's API with an OAuth token | No connector runtime needed here, so there is no firewall consideration. |

## Camunda 8 Run (recommended to start)

```bash
./start.sh        # Windows: start.bat
```
Deploy all 18 resources (4 BPMN, 1 DMN, 13 forms) from Desktop Modeler, then start
`UnderwritingIssuance`. The helper script defaults to `http://localhost:8080` with `demo:demo`.

## Docker Compose (Self-Managed)

Use the official `camunda/camunda-platform` compose file. Deploy the same way, then point the script at
the right port:

```bash
C8_REST_BASE=http://localhost:8080 ./scripts/simulate-client-response.sh 123456789
```

## Self-Managed on Kubernetes (Helm)

Deploy to the in-cluster gateway (Modeler over a port-forward, or `zbctl` / the REST API from CI). To
publish the client message, call `POST /v2/messages/publication` on the gateway with a token from your
identity provider. Nothing in the model changes.

## SaaS

Deploy from Web or Desktop Modeler. To publish the client message, get an OAuth token for the cluster
and call the same `POST /v2/messages/publication` endpoint on the cluster's API URL.

Because this example uses **no connectors**, the usual SaaS question of "can the connector runtime
reach my internal systems" does not arise. It becomes relevant the moment you replace a human step with
a REST or Email connector (see the "where the example deliberately stops" section of the README): at
that point the connector runtime location matters, and on SaaS you would either expose the target
system or run a hybrid self-managed connector runtime inside your network.

## Reference bindings

Forms, the DMN and the called processes are referenced with `bindingType="latest"`, which is forgiving
while you iterate: deploy files in any order, update a single form without redeploying the process. For
production, switch to `bindingType="deployment"` (or `versionTag`) so each process version pins the
exact form and decision versions it was tested with, and deploy all resources together in one
deployment.

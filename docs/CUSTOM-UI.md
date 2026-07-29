# Putting your own React or Angular UI on top

This example uses **Camunda Tasklist** for the human steps, so it runs with nothing to build. That is
a convenience, not a constraint. Camunda is **headless**: the engine has no opinion about your UI, and
Tasklist is just one client of a public API that your own application can call instead.

This document is the map for that. It is intentionally a starting point, the deeper walkthrough is
what a dedicated headless session is for.

## The point

Today your screens probably decide the order of work: which page comes next, which fields are
required, when something can be approved. That logic is spread across components and is expensive to
change.

With Camunda, **the model decides and your UI renders**. Your application asks "what is the next task
for this user?", renders it, and posts the result back. When the process changes, you change the
diagram, not the frontend. The three workflows in this repo already work that way: nothing in the
model knows or cares whether a human completes a task from Tasklist, from your React app, or from a
script.

## Three integration patterns

Pick per screen. They mix freely in the same process.

| Pattern | You build | Best for |
|---|---|---|
| **1. Use Tasklist** | nothing | internal, low-volume, back-office steps. What this repo does today. |
| **2. Your app shell, Camunda Forms rendered inside it** | the shell, navigation and styling | you want your own look and navigation but not to hand-build every field. The forms in `forms/` render inside your app with the official `@bpmn-io/form-js` library. |
| **3. Fully custom screens** | the screens | high-volume or complex screens where the UX matters, for example the offering capture steps. You call the task API directly and render whatever you like. |

Pattern 2 is the one people underestimate: you keep your application, and the 13 forms in this repo
render inside it unchanged, because a Camunda Form is just JSON.

## The API surface you actually need

Everything below is the Camunda 8 **REST API v2**, the same API Tasklist itself uses. Base URL is
`http://localhost:8080` for Camunda 8 Run.

| What you want | Call |
|---|---|
| Start a lifecycle instance | `POST /v2/process-instances` with `processDefinitionId: "UnderwritingIssuance"` |
| Get the work queue for a user or group | `POST /v2/user-tasks/search` filtered by `candidateGroup`, `assignee` or `state: "CREATED"` |
| Get one task, including its `formKey` and variables | `GET /v2/user-tasks/{userTaskKey}` |
| Fetch the form schema to render | `GET /v2/forms/{formKey}` |
| Claim a task | `POST /v2/user-tasks/{userTaskKey}/assignment` |
| Complete a task with the collected data | `POST /v2/user-tasks/{userTaskKey}/completion` with `{ "variables": { ... } }` |
| Resume the client-response wait | `POST /v2/messages/publication` (see `scripts/simulate-client-response.sh`) |
| Read instance state for a status view | `POST /v2/process-instances/search`, `POST /v2/variables/search` |

Check the [REST API reference](https://docs.camunda.io/docs/apis-tools/camunda-api-rest/camunda-api-rest-overview/)
for the exact request shapes on your version, they are stable but do gain fields.

## The loop, in about 30 lines

This is the whole idea. Fetch the queue, render the engine's form, post the result back, refresh.
Nothing here encodes the process order.

```jsx
// React. The equivalent Angular service is the same four calls.
import { useEffect, useState } from 'react';
import { Form } from '@bpmn-io/form-js';        // npm i @bpmn-io/form-js

const api = (path, body) =>
  fetch(`/camunda/v2${path}`, {                  // proxied by your backend, see "Do not call from the browser"
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).then(r => r.json());

export function WorkQueue({ group, container }) {
  const [tasks, setTasks] = useState([]);

  const load = () =>
    api('/user-tasks/search', { filter: { state: 'CREATED', candidateGroup: group } })
      .then(res => setTasks(res.items ?? []));

  useEffect(() => { load(); }, [group]);

  async function open(task) {
    // The engine tells you which form to show. Your UI does not decide.
    const schema = await fetch(`/camunda/v2/forms/${task.formKey}`).then(r => r.json());
    const form = new Form({ container });
    await form.importSchema(schema, task.variables ?? {});

    form.on('submit', async ({ data, errors }) => {
      if (Object.keys(errors).length) return;
      await api(`/user-tasks/${task.userTaskKey}/assignment`, { assignee: 'me', action: 'assign' });
      await api(`/user-tasks/${task.userTaskKey}/completion`, { variables: data });
      load();                                    // the model has already moved on
    });
  }

  return (
    <ul>
      {tasks.map(t => (
        <li key={t.userTaskKey} onClick={() => open(t)}>
          {t.name} <small>{t.candidateGroups?.join(', ')}</small>
        </li>
      ))}
    </ul>
  );
}
```

Swap the `Form` import for your own components and you have pattern 3. Keep it and you have pattern 2.

## Do not call Camunda from the browser

Put a **thin backend between your UI and Camunda**. It is a few dozen lines and it exists to:

- hold the credentials or OAuth client secret, which must never reach the browser,
- exchange them for a token and cache it,
- avoid CORS entirely, since your UI calls your own origin,
- narrow what the frontend is allowed to do, for example only the current user's queue.

```
React / Angular  ──►  your backend (BFF)  ──►  Camunda 8 REST API v2
   your UI            auth, token cache          user tasks, forms,
   your routing       request narrowing          messages, instances
```

For Camunda 8 Run locally, the backend authenticates with basic auth (`demo:demo` by default). On
Self-Managed and SaaS it is OAuth client credentials. Same code, different credentials.

## Mapping this repo to screens

If you were to build a UI for these three workflows:

| Workflow | Likely pattern | Why |
|---|---|---|
| **Offering Capture** | 3, fully custom | Data-heavy entry with lookups and validation. This is where your own UX earns its keep, and where a wizard driven by the engine's "what's next" beats hardcoded navigation. |
| **Settlement Eligibility** approvals | 1 or 2 | Approvals are small, structured decisions. Tasklist or Camunda Forms in your shell is usually enough, with the queue per role you already have. |
| **Agent Confirmation** comparison | 3, fully custom | The side-by-side comparison of recorded and client-confirmed values deserves a purpose-built screen. |

Note that all three coexist. You do not have to choose one pattern for the whole application.

## Worth covering in a headless session

- The "ask the engine what is next" pattern, live, and what it removes from your frontend.
- Rendering these exact forms inside a React and an Angular shell.
- Task lists per persona, including claiming, priorities and filters.
- A live status view for an instance, driven by the process rather than a status column.
- Auth patterns and where the BFF boundary belongs.
- What stays in the model versus what stays in the UI, and how to tell.

## Reference

- [Camunda 8 REST API v2](https://docs.camunda.io/docs/apis-tools/camunda-api-rest/camunda-api-rest-overview/)
- [form-js, the library Tasklist uses to render Camunda Forms](https://github.com/bpmn-io/form-js)
- [bpmn-js, if you want to embed the live diagram in your own UI](https://github.com/bpmn-io/bpmn-js)
- [Building custom task applications](https://docs.camunda.io/docs/components/tasklist/introduction-to-tasklist/)

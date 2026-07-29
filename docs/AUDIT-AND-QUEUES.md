# Audit history and persona queues

Two claims worth being able to demonstrate on demand: **personas work from queues**, and **the
lifecycle is auditable end to end**. Both are native to Camunda 8 here, with nothing custom to build.

## Personas work from queues

Every user task in this example declares a candidate group:

```xml
<zeebe:assignmentDefinition candidateGroups="legal-counsel" />
```

That is the queue. In **Tasklist**, a user sees the tasks for the groups they belong to, and can filter
by process, candidate group, assignee, or due date. Nobody is emailed a spreadsheet and nobody hunts
through a shared inbox: the work arrives in the right queue because the model said who owns the step.

| Queue | Owns |
|---|---|
| `uw-analysts` | ECD: Enter CUSIP, Offering Info, Security Info, Summary and Submit |
| `compliance-officers` | Compliance Review (only when the DMN says REVIEW) |
| `legal-counsel` | Legal Approval |
| `crediting-participants` | Crediting Participant Approval |
| `uw-operations` | Register Settlement Eligibility, Send Confirmation Email, Compare to Closing Docs, Update Masterfile |
| `underwriting-supervisors` | Supervisor Review, and every overdue Escalation Review |

Tasks also carry a **priority** (`zeebe:priorityDefinition`), so a queue can be sorted by urgency:
escalation reviews are 90, corrections 80, approvals 70, capture steps 50.

To try this on Camunda 8 Run, assign your local user to a group, or just claim tasks as the demo user
and filter by candidate group.

## The lifecycle is auditable

**Operate** is the audit view. For any instance you get:

- the **path actually taken** through the diagram, highlighted, including which gateway branch was
  chosen and why (the variables are right there),
- **every activity** with its **start and end timestamp**,
- the **DMN decision** that was evaluated, with its inputs and outputs, so you can show *why*
  compliance cleared or was routed to review,
- the **variables** at each point, including the client-confirmed values and the comparison outcome,
- **incidents**, if anything failed,
- the parent/child relationship for the three called workflows, so you can click from the lifecycle
  instance into the ECD, Settlement Eligibility or Agent Confirmation instance.

Who did what comes from the task data: Tasklist records the **assignee** and completion time for each
task, alongside the candidate group that owned it. Combined with the form values (each decision field
and its notes are stored as process variables), that is the "every task, assignee group, decision and
timestamp" record.

### Naming that makes the audit trail readable

Decisions are stored as explicit variables rather than a generic flag, which is what makes the history
legible later: `complianceDecision`, `legalDecision`, `cpDecision`, `valuesMatch`,
`supervisorDecision`, `escalationAction`, each with a matching notes field
(`legalNotes`, `comparisonNotes`, and so on). Every reviewer's rationale is captured as a required
field, so the trail explains itself.

### If you need audit data outside Camunda

Two standard routes, neither of which changes the model:

- **Operate / Camunda APIs** to query history on demand.
- **Exporters** to stream the engine's event stream into your own warehouse or archive if you need
  long-term retention under your own controls.

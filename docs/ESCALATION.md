# Overdue task escalation

The requirement: *if a task is overdue, create an escalation task*, without stopping the original
task, and without copy-pasting the same escalation branch next to every approval.

## How it is modeled

Per monitored task, two elements:

1. A **non-interrupting timer boundary event** (`cancelActivity="false"`). Non-interrupting is the
   whole point: the timer fires, the original task keeps running and stays workable.
2. An **escalation end event** that raises the shared escalation code `TASK_OVERDUE`.

Once per process, one handler:

3. A process-level **event sub-process** (`triggeredByEvent="true"`) whose start event is a
   **non-interrupting escalation start event** catching `TASK_OVERDUE`, routing to a single
   **Escalation Review** user task owned by `underwriting-supervisors`.

```
[ Legal Approval ]───(timer, non-interrupting)───▶(( escalate TASK_OVERDUE ))
[ CP Approval    ]───(timer, non-interrupting)───▶(( escalate TASK_OVERDUE ))
        ...                                                    │
                                              propagates by escalation code
                                                               ▼
   ┌───────────────── event sub-process (non-interrupting) ─────────────────┐
   │  (escalation start) ──▶ [ Escalation Review ] ──▶ (end)                │
   └────────────────────────────────────────────────────────────────────────┘
```

Escalation propagates to the enclosing scope by **escalation code**, so there is deliberately **no
sequence flow** between the throwing end events and the event sub-process. Drawing one would be
wrong: it misrepresents BPMN semantics and clutters the diagram.

## Why escalation events and not a message

A common way to draw this is a message throw event caught by a message event sub-process. It reads
fine, but in Camunda 8 a plain intermediate **message throw** event does not publish an internally
correlated message, so that version would never actually fire, and a message catch would also need a
correlation key. **Escalation events are the executable construct for this**: same centralized shape,
no correlation key, and it genuinely runs. This is the one place where this repo deviates from the
"message throw and catch" drawing convention, on purpose.

## Tuning it

- **Durations** are `PT2M` in every timer so escalation is visible during a demo. For real use, replace
  the literal with an expression, for example `=slaDueAt` (a date) or `=escalationDuration` (a
  duration), and set that variable per instance from your SLA policy or a business calendar.
- **Which tasks are monitored** is a per-task decision: attach a boundary timer where an SLA exists.
  Settlement Eligibility monitors all four approval steps; Agent Confirmation monitors the client-response
  wait and the comparison.
- **What escalation does** is one place to change. Today it creates a supervisor task; it could equally
  notify a channel, reassign, or write to a dashboard, by editing the single event sub-process.
- **Repeat escalation:** a boundary timer with a duration fires once. For "nag every day until done",
  use a timer **cycle** (for example `R/PT24H`) on the boundary event.

## Why the client-response wait is a receive task

"Wait for client response" is a `receiveTask`, not a plain intermediate message catch event. Both wait
for the same message, but a receive task is an *activity*, so a boundary timer can be attached to it.
That is what lets an unanswered client email escalate like any other overdue task.

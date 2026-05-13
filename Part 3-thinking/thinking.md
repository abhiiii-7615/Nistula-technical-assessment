# Part 3 — Thinking Questions

**Scenario:** It is 3am. A guest at Villa B1 sends a WhatsApp message:
> "There is no hot water and we have guests arriving for breakfast in 4 hours. This is unacceptable. I want a refund for tonight."

---

## Question A — The Immediate Response

**The message sent at 3am:**

> Hi! I'm really sorry, no hot water at 3am with guests arriving is completely unacceptable and I understand your frustration. I have escalated this to our team right away and someone will be in touch with you within 15 minutes with a fix. We’ll get that fixed right away.

**Why this wording:**

The reply opens with a genuine acknowledgement, not a corporate apology — "completely unacceptable" mirrors the guest's own language, which signals that the system actually understood the severity rather than shooting a generic response. The 15 minutes promise is something solid and actionable, giving the guest something concrete to hold onto at 3am rather than vague reassurance. The refund request is not ignored, but neither is it promised outright.

---

## Question B — The System Design

**What happens the moment the message is received:**

**1. Classification and escalation**
The keyword classifier immediately identifies `complaint` as the query type. Because the query type is `complaint`, the action is forced to `escalate` regardless of confidence score. The AI drafts a reply but does not auto-send it — a human must approve or the timer triggers (see below).

**2. Who gets notified**
Within 30 seconds of the message arriving:
- The on-call property manager receives a push notification and SMS with the guest name, property, and message text
- The caretaker for Villa B1 receives an SMS — the geyser may need a manual reset
- A Slack alert fires to the `#escalations` channel with full message context and a direct link to the conversation

**3. What gets logged**
The following is written to the database immediately:
- Inbound message stored with `query_type = complaint`, `classifier_source = keyword`
- Conversation status updated to `escalated`
- A complaint event record created with `property_id = villa-b1`, `category = hot_water`, `timestamp`, `booking_ref`
- The AI drafted reply stored with `outbound_status = ai_drafted`, not yet sent

**4. If no human responds within 30 minutes**
The platform runs a background job that checks every 5 minutes for escalated conversations with no outbound message sent. At the 30-minute mark:
- The AI drafted reply is automatically sent to the guest so they are not left in silence — `outbound_status` updated to `auto_sent`
- A second escalation alert fires to the property manager's personal phone number via SMS, flagged as overdue
- The conversation is reassigned to a senior agent queue

---

## Question C — The Learning

**What the system should detect:**

Three hot water complaints at Villa B1 within two months is not bad luck — it is a pattern. The platform should be running a background aggregation job that groups complaint events by `property_id` and `category` on a rolling 60-day window. When the same category crosses a threshold (e.g. 2+ complaints at the same property), it raises a property health flag.

**What gets triggered on the third complaint:**

- A `property_issue` record is created in the database: `property = villa-b1`, `issue_category = hot_water`, `complaint_count = 3`, `first_reported`, `last_reported`
- The operations team receives a summary report: dates, guest names, booking refs, and the exact complaint text from all three incidents
- The caretaker is scheduled for a mandatory geyser inspection before the next check-in, tracked as a task that must be marked complete before the booking is confirmed active
- Villa B1 is flagged internally — any new booking triggers a pre-arrival checklist item: "verify hot water operational"

**What I would build to prevent a fourth complaint:**

A lightweight property maintenance tracker with three components:

1. **Complaint pattern detector** — a daily job that scans the messages table for complaints grouped by property and category. If the same issue appears twice at the same property within 60 days, it raises a flag automatically. No human has to notice the pattern.

2. **Pre-arrival checklist** — a simple checklist per property that the caretaker completes 24 hours before every check-in. For Villa B1, "hot water working" becomes a permanent checklist item until three consecutive checks pass with no complaint. The caretaker confirms via a WhatsApp message to the platform bot; the response is logged.

3. **Guest early-warning message** — if a maintenance check has not been completed within 12 hours of check-in, the platform automatically alerts the property manager and holds the booking in a `pending_verification` state. The guest is not checked in until the caretaker confirms.


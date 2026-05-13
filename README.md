# Nistula Technical Assessment — Abhinav Reddy Bolla

## Part 1 — Guest Message Handler

### Setup
1. Clone the repo
2. Run `npm install`
3. Create `.env` from `.env.example`
4. Add your `ANTHROPIC_API_KEY`
5. Run `npm start`

### Confidence Scoring Logic
Claude returns a `confidence_score` between **0.0** and **1.0** for how sure the model is that the drafted reply is appropriate and safe to use as-is. That number is not interpreted in isolation: **`complaint` is always treated as sensitive**, so it never auto-sends regardless of score.

- Claude returns a raw score between 0 and 1
- complaint always → escalate regardless of score
- score >= 0.85 → auto_send
- score 0.60–0.84 → agent_review
- score < 0.60 → escalate

So high confidence non-complaints can go straight out; the middle band always gets a human glance; low confidence or any complaint goes to a person.

### Keyword Pre-classifier
Before calling Claude, `classifyMessage` scans the lowercased guest text against small keyword lists in `classifier.js`.

- **Complaints first:** if any complaint-related phrase matches (for example "refund", "broken", "unhappy"), the type is set to `complaint` immediately so the model focuses on tone and escalation-safe wording, not on debating whether it is a complaint.
- **Other intents:** non-overlapping rules map phrases to `post_sales_checkin`, `pre_sales_pricing`, `pre_sales_availability`, or `special_request`.
- **Ambiguity:** if **no** rule matches, or **more than one** non-complaint category matches, the classifier returns `null`. In that case the service prompt asks Claude to classify among the full set of types including `general_enquiry`.

### Test Results
Screenshots from exercising the webhook (payload shape, drafted reply, score, and `action`).

#### Test 1 — Pre-sales Availability
![Test 1](<Screenshots (testcases)/testcase-1.jpeg>)

#### Test 2 — Complaint (escalate)
![Test 2](<Screenshots (testcases)/testcase-2.jpeg>)

#### Test 3 — General Enquiry
![Test 3](<Screenshots (testcases)/testcase-3.jpeg>)

---

## Part 2 — Database Schema
*See schema.sql*

---

## Part 3 — Thinking Questions
*See thinking.md*

---

## Future Work — ML Classifier

The current keyword pre-classifier is intentionally simple: it covers obvious cases well but has no understanding of phrasing variations or context. The planned upgrade is a lightweight **Naive Bayes text classifier** trained on labelled guest messages.

### Why Naive Bayes
For 6 well-defined, domain-specific categories, Naive Bayes performs surprisingly well. It is fast, requires no GPU, runs in-process alongside the Express server, and produces a probability score per class that maps directly onto the existing confidence scoring logic. A fine-tuned transformer (e.g. DistilBERT) would be more powerful but is overkill at this stage.

### The training data problem — and how to solve it
The core challenge is labelled data: Naive Bayes needs roughly 50–100 examples per category to generalise reliably. Since the platform is new and has no real traffic yet, the bootstrap plan is:

1. **Synthetic generation** — use Claude to generate ~180 realistic guest messages (30 per category), varying tone, formality, and phrasing. This gives enough signal to train a usable first model immediately.
2. **Organic labelling** — every real inbound message that passes through the webhook is stored in the database with its `query_type` and `classifier_source`. After a few weeks of live traffic, this becomes a growing set of real, naturally labelled examples.
3. **Periodic retraining** — as real data accumulates, the model is retrained on the combined synthetic + real dataset. Over time the synthetic examples are phased out entirely.

### How it fits into the existing pipeline
The ML model would be a drop-in replacement for `classifier.js`. The function signature stays identical:

```
classifyMessage(text: string) → query_type | null
```

The model returns a predicted class and a probability score. If the top-class probability is above a threshold (e.g. 0.75), the prediction is used directly. If it falls below that threshold — meaning the model is uncertain — the function returns `null` and Claude classifies as it does today. The confidence gate means the ML model never silently misfires; low-confidence predictions always fall back to the LLM.
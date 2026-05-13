# Nistula Technical Assessment — Abhinav Reddy Bolla

## Part 1 — Guest Message Handler

### Setup
1. Clone the repo
2. Run `npm install`
3. Create `.env` from `.env.example`
4. Add your `ANTHROPIC_API_KEY`
5. Run `npm start`

### Architecture
Brief explanation of your file structure and why you structured it that way.

### Confidence Scoring Logic
Explain YOUR logic here — this is explicitly asked for in the brief.
Example:
- Claude returns a raw score between 0 and 1
- complaint always → escalate regardless of score
- score >= 0.85 → auto_send
- score 0.60–0.84 → agent_review  
- score < 0.60 → escalate

### Keyword Pre-classifier
Explain why you added it — saves tokens, faster response for obvious cases,
Claude only called for ambiguous messages.

### Test Results
#### Test 1 — Pre-sales Availability
![Test 1](screenshots/test1.png)

#### Test 2 — Complaint (escalate)
![Test 2](screenshots/test2.png)

#### Test 3 — General Enquiry
![Test 3](screenshots/test3.png)

---

## Part 2 — Database Schema
*See schema.sql*

---

## Part 3 — Thinking Questions
*See thinking.md*
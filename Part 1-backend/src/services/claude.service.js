import Anthropic from '@anthropic-ai/sdk';
import env from '../config/environment.js';

const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });


const SYSTEM_PROMPT_BASE = `You are a hospitality AI for Villa B1,Assagao,North Goa.
Property: Villa B1, Assagao, North Goa
Bedrooms: 3 | Max guests: 6 | Private pool: Yes
Check-in: 2pm | Check-out: 11am
Base rate: INR 18,000 per night (up to 4 guests)
Extra guest: INR 2,000 per night per person
WiFi password: Nistula@2024
Caretaker: Available 8am to 10pm
Chef on call: Yes, pre-booking required
Availability April 20-24: Available
Cancellation: Free up to 7 days before check-in`;

const TASK_WHEN_QUERY_TYPE_KNOWN = `TASK: The guest message has already been classified. query_type is fixed — use exactly the value given in the user content line "Query type:". You must ONLY draft the reply and return confidence_score; do not re-classify. Output ONLY a single minified JSON — no markdown, no prose:
{"query_type":"<use the provided value>","drafted_reply":"<REPLY>","confidence_score":<0.0-1.0>}
drafted_reply must be warm, concise, professional, ≤3 sentences.`;

const TASK_WHEN_QUERY_TYPE_UNKNOWN = `TASK: Analyse the guest message. Output ONLY a single minified JSON — no markdown, no prose:
{"query_type":"<TYPE>","drafted_reply":"<REPLY>","confidence_score":<0.0-1.0>}
VALID query_types: pre_sales_availability|pre_sales_pricing|post_sales_checkin|special_request|complaint|general_enquiry
drafted_reply must be warm, concise, professional, ≤3 sentences.`;

/**
 * Derives a routing action from the confidence score and query type.
 * - complaint             → always escalate (human must handle)
 * - confidence >= 0.85   → auto_send
 * - confidence 0.60–0.84 → agent_review
 * - confidence < 0.60    → escalate
 *
 * @param {number} confidence_score
 * @param {string} query_type
 * @returns {'auto_send'|'agent_review'|'escalate'}
 */
function deriveAction(confidence_score, query_type) {
  if (query_type === 'complaint' || confidence_score < 0.60) return 'escalate';
  if (confidence_score >= 0.85) return 'auto_send';
  return 'agent_review';
}

export async function analyseAndDraft(normalizedMessage) {
  const query_type = normalizedMessage.query_type;

  const system =
    SYSTEM_PROMPT_BASE +
    (query_type != null ? TASK_WHEN_QUERY_TYPE_KNOWN : TASK_WHEN_QUERY_TYPE_UNKNOWN);

  const userContent =
    `Query type: ${query_type ?? 'unknown — please classify'}\n` +
    `Guest: ${normalizedMessage.guest_name}\n` +
    `Booking: ${normalizedMessage.booking_ref ?? 'none'}\n` +
    `Message: ${normalizedMessage.message_text}`;

  const response = await client.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 256,
    system,
    messages: [{ role: 'user', content: userContent }],
  });

  const rawText = response.content
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join('');

  // Strip any accidental markdown fences before parsing
  const cleaned = rawText.replace(/```(?:json)?|```/gi, '').trim();

  let parsed;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    throw new Error(`Malformed JSON from Claude: ${rawText}`);
  }

  const {
    query_type: model_query_type,
    drafted_reply,
    confidence_score,
  } = parsed;

  if (!model_query_type || !drafted_reply || confidence_score === undefined) {
    throw new Error(`Incomplete fields in Claude response: ${rawText}`);
  }

  const action = deriveAction(confidence_score, model_query_type);

  return {
    query_type: model_query_type,
    drafted_reply,
    confidence_score,
    action,
  };
}
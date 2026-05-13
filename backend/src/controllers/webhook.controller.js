import { normalizePayload } from '../utils/normalizer.js';
import { classifyMessage } from '../utils/classifier.js';
import { analyseAndDraft } from '../services/claude.service.js';

/**
 * POST /webhook/message
 * Returns message_id, query_type, drafted_reply, confidence_score, and action only.
 */
export async function handleIncomingMessage(req, res) {
  try {
    const normalizedMessage = normalizePayload(req.body);
    normalizedMessage.query_type = classifyMessage(normalizedMessage.message_text);
    //console.log(normalizedMessage);
    if (!normalizedMessage.message_text) {
      return res.status(400).json({
        success: false,
        error: 'message_text is required and must not be empty.',
      });
    }

    const aiResult = await analyseAndDraft(normalizedMessage);

    return res.status(200).json({
      message_id: normalizedMessage.message_id,
      query_type: aiResult.query_type,
      drafted_reply: aiResult.drafted_reply,
      confidence_score: aiResult.confidence_score,
      action: aiResult.action,
    });
  } catch (err) {
    console.error('[WebhookController] Error:', err.message);

    return res.status(500).json({
      success: false,
      error: 'An internal server error occurred while processing the message.',
      detail: err.message,
    });
  }
}

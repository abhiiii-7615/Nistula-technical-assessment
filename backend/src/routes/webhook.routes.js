import { Router } from 'express';
import { handleIncomingMessage } from '../controllers/webhook.controller.js';

const router = Router();

// POST /webhook/message
router.post('/message', handleIncomingMessage);

export default router;

import express from 'express';
import webhookRoutes from './routes/webhook.routes.js';

const app = express();

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Routes 
app.use('/webhook', webhookRoutes);

// Health check
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// 404 handler 
app.use((_req, res) => res.status(404).json({ success: false, error: 'Route not found.' }));

// Global error handler
app.use((err, _req, res, _next) => {
  console.error('[GlobalErrorHandler]', err.stack);
  res.status(500).json({ success: false, error: 'Unexpected server error.', detail: err.message });
});

export default app;

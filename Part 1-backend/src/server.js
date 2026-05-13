import env from './config/environment.js';  // Validates API key 
import app from './app.js';

const PORT = env.PORT;
const MODE = env.NODE_ENV;

app.listen(PORT, () => {
  console.log(`[Server] Running in ${MODE} mode on http://localhost:${PORT}`);
  console.log(`[Server] Webhook endpoint: POST http://localhost:${PORT}/webhook/message`);
});

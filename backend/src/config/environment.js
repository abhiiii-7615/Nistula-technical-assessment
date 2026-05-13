import dotenv from 'dotenv';

dotenv.config();

const { ANTHROPIC_API_KEY, PORT, NODE_ENV } = process.env;

if (!ANTHROPIC_API_KEY) {
  throw new Error('FATAL: ANTHROPIC_API_KEY is not set in environment variables.');
}

export default {
  ANTHROPIC_API_KEY,
  PORT: Number(PORT),
  NODE_ENV,
};

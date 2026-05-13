import { randomUUID } from 'crypto';

/**
 * Maps an incoming webhook payload to the Unified Message Schema.
 * Accepts fields from multiple possible source formats (Airbnb, Booking.com, direct, etc.)
 * @param {Object} payload - Raw incoming request body
 * @returns {Object} Unified message schema
 */
export function normalizePayload(payload) {
  return {
    message_id:   randomUUID(),
    source:       payload.source        ?? 'unknown',
    guest_name:   payload.guest_name    ?? 'Guest',
    message_text: payload.message     ?? '',
    timestamp:    payload.timestamp     ?? new Date().toISOString(),
    booking_ref:  payload.booking_ref   ?? payload.reservation_id ?? null,
    property_id:  payload.property_id   ?? null,
  };
}

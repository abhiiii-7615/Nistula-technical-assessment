const COMPLAINT_KEYWORDS = [
  'not working',
  'unhappy',
  'broken',
  'issue',
  'problem',
  'complaint',
  'unacceptable',
  'disappointed',
  'refund',
  'rude',
];

const NON_COMPLAINT_RULES = [
  {
    query_type: 'post_sales_checkin',
    keywords: [
      'check-in',
      'checkout',
      'wifi',
      'wi-fi',
      'password',
      'keys',
      'caretaker',
      'arrival',
      'check in',
      'check out',
    ],
  },
  {
    query_type: 'pre_sales_pricing',
    keywords: [
      'rate',
      'cost',
      'price',
      'how much',
      'charge',
      'tariff',
      'per night',
      'total amount',
      'fees',
    ],
  },
  {
    query_type: 'pre_sales_availability',
    keywords: [
      'available',
      'availability',
      'vacancy',
      'vacant',
      'free on',
      'book',
      'open on',
      'slot',
    ],
  },
  {
    query_type: 'special_request',
    keywords: [
      'early check',
      'late check',
      'airport transfer',
      'chef',
      'arrange',
      'request',
      'birthday',
      'anniversary',
    ],
  },
];

function matchesAny(lower, keywords) {
  for (let i = 0; i < keywords.length; i += 1) {
    if (lower.includes(keywords[i])) return true;
  }
  return false;
}

/**
 * Keyword-based pre-classification of guest messages. Complaint is always
 * evaluated first; if multiple non-complaint categories match, returns null.
 *
 * @param {string} text - Raw guest message text
 * @returns {string|null} One of the known query_type strings, or null when ambiguous or unmatched
 */
export function classifyMessage(text) {
  const lower = String(text).toLowerCase();

  if (matchesAny(lower, COMPLAINT_KEYWORDS)) {
    return 'complaint';
  }

  const matchedTypes = [];
  for (let r = 0; r < NON_COMPLAINT_RULES.length; r += 1) {
    const rule = NON_COMPLAINT_RULES[r];
    if (matchesAny(lower, rule.keywords)) {
      matchedTypes.push(rule.query_type);
    }
  }

  if (matchedTypes.length === 1) {
    return matchedTypes[0];
  }

  return null;
}

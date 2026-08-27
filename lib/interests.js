export const INTEREST_KINDS = Object.freeze(['book', 'movie', 'topic'])
export const MAX_INTERESTS_PER_PROFILE = 36
export const MAX_INTERESTS_PER_KIND = 12
export const INTEREST_LABEL_MAX_LENGTH = 160

export function isInterestKind(value) {
  return INTEREST_KINDS.includes(String(value || '').toLowerCase())
}

export function normalizeInterestKind(value) {
  const kind = String(value || '').trim().toLowerCase()
  return isInterestKind(kind) ? kind : null
}

export function interestKindLabel(kind) {
  return kind === 'book' ? 'كتب' : kind === 'movie' ? 'أفلام' : kind === 'topic' ? 'مواضيع' : 'اهتمامات'
}

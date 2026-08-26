/**
 * One line per failure, in a shape the hosting platform's log search can
 * filter on.
 *
 * Most API routes used to answer 500 without recording anything, so the only
 * evidence a request had failed was a person saying so. Every entry starts
 * with the same prefix and carries the route that failed and the provider's
 * own error code, which is what turns "the site is broken" into a query.
 *
 * Never include the request body, an email address, or anything a person
 * typed: these lines are readable by anyone with dashboard access.
 */
const PREFIX = '[openly]'

function detailsOf(error) {
  if (!error) return {}
  // PostgREST and GoTrue both answer with { code, message, details, hint }.
  const { code, message, details, hint, status } = error
  return {
    code: code || undefined,
    status: status || undefined,
    message: typeof message === 'string' ? message.slice(0, 300) : undefined,
    details: typeof details === 'string' ? details.slice(0, 300) : undefined,
    hint: typeof hint === 'string' ? hint.slice(0, 200) : undefined
  }
}

/**
 * @param {string} event dot-separated route identifier, e.g. "timeline.load"
 * @param {unknown} error the provider error, or any thrown value
 */
export function logError(event, error) {
  const entry = { level: 'error', event, ...detailsOf(error) }
  for (const key of Object.keys(entry)) if (entry[key] === undefined) delete entry[key]
  console.error(PREFIX, JSON.stringify(entry))
}

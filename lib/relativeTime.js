const formats = {
  ar: new Intl.RelativeTimeFormat('ar', { numeric: 'auto' }),
  en: new Intl.RelativeTimeFormat('en', { numeric: 'auto' })
}

export function formatRelativeTime(value, language = 'ar', now = Date.now()) {
  const timestamp = new Date(value).getTime()
  if (!Number.isFinite(timestamp)) return ''
  const elapsed = timestamp - now
  const absolute = Math.abs(elapsed)
  const format = formats[language === 'en' ? 'en' : 'ar']
  if (absolute < 45_000) return format.format(0, 'second')
  let unit = 'minute'
  let divisor = 60_000

  if (absolute >= 365 * 24 * 60 * 60_000) {
    unit = 'year'
    divisor = 365 * 24 * 60 * 60_000
  } else if (absolute >= 30 * 24 * 60 * 60_000) {
    unit = 'month'
    divisor = 30 * 24 * 60 * 60_000
  } else if (absolute >= 24 * 60 * 60_000) {
    unit = 'day'
    divisor = 24 * 60 * 60_000
  } else if (absolute >= 60 * 60_000) {
    unit = 'hour'
    divisor = 60 * 60_000
  }

  const amount = elapsed < 0 ? Math.ceil(elapsed / divisor) : Math.floor(elapsed / divisor)
  return format.format(amount || 0, unit)
}

export const SAFE_AUTH_CAPABILITIES = Object.freeze({
  email: true,
  emailOtp: false,
  phone: false,
  google: false,
  apple: false
})

export function mapAuthCapabilities(settings, emailMode = process.env.AUTH_EMAIL_MODE) {
  const external = settings?.external || {}
  const mode = emailMode === 'link' ? 'link' : 'otp'
  const email = external.email === true

  return {
    email,
    emailOtp: email && mode === 'otp',
    emailMode: email ? mode : 'disabled',
    phone: external.phone === true,
    google: external.google === true,
    apple: external.apple === true
  }
}

// The fail-closed payload must carry every field mapAuthCapabilities returns.
// It was missing `emailMode`, so the same endpoint answered with two different
// shapes: the native client decodes emailMode as a non-optional String and threw
// the whole response away, and the web read `undefined` and told people to wait
// for a sign-in link while the server was sending a code.
export const SAFE_AUTH_CAPABILITIES = Object.freeze({
  email: true,
  emailOtp: false,
  emailMode: 'link',
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

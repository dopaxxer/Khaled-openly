export default function manifest() {
  return {
    name: 'Openly',
    short_name: 'Openly',
    description: 'شبكة نصية عامة للأفكار والذوق والمحادثة، بلا خوارزمية ترتيب.',
    start_url: '/',
    display: 'standalone',
    background_color: '#f4f5f4',
    theme_color: '#f4f5f4',
    icons: [{ src: '/icon.png', sizes: '512x512', type: 'image/png', purpose: 'any' }],
    lang: 'ar',
    dir: 'rtl'
  }
}

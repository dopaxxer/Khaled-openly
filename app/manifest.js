export default function manifest() {
  return {
    name: 'Openly',
    short_name: 'Openly',
    description: 'شبكة نصية عامة بلا خوارزمية ترتيب.',
    start_url: '/',
    display: 'standalone',
    background_color: '#f7f8fb',
    theme_color: '#082f8f',
    lang: 'ar',
    dir: 'rtl',
    icons: [
      { src: '/openly-mark.webp', sizes: '256x256', type: 'image/webp', purpose: 'any maskable' }
    ]
  }
}

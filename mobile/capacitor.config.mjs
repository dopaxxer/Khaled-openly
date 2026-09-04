const serverUrl = process.env.MOBILE_SERVER_URL || 'https://openli-git-claude-website-desig-b9c762-khaled-algabris-projects.vercel.app'

export default {
  appId: 'ink.openly.app',
  appName: 'Openly',
  webDir: 'www',
  server: {
    url: serverUrl,
    cleartext: false
  }
}

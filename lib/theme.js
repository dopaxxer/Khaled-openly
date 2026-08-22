export const THEME_STORAGE_KEY = 'openly-theme'
export const THEME_OPTIONS = ['system', 'light', 'dark']

export function isThemePreference(value) {
  return THEME_OPTIONS.includes(value)
}

// Runs before first paint, inlined in <head>. Without it the page renders in
// the device theme for a frame and then snaps to the stored choice.
export const THEME_BOOT_SCRIPT = `(function(){try{var t=localStorage.getItem('${THEME_STORAGE_KEY}');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t)}catch(e){}})()`

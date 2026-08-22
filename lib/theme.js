export const THEME_STORAGE_KEY = 'openly-theme'
export const THEME_OPTIONS = ['system', 'light', 'dark']

export function isThemePreference(value) {
  return THEME_OPTIONS.includes(value)
}

export const COLOR_THEME_STORAGE_KEY = 'openly-color-theme'

// 'ultramarine' is the default accent sampled from the logo itself, so it has
// no data-color-theme value of its own — its colours live directly on :root.
export const COLOR_THEMES = [
  { value: 'ultramarine', label: 'أزرق ملكي', swatch: '#16277a' },
  { value: 'crimson', label: 'عنّابي', swatch: '#b8244c' },
  { value: 'forest', label: 'غابي', swatch: '#1f7a42' },
  { value: 'amber', label: 'كهرماني', swatch: '#b3760f' },
  { value: 'violet', label: 'بنفسجي', swatch: '#7c3aed' }
]

export function isColorTheme(value) {
  return COLOR_THEMES.some(t => t.value === value)
}

// Runs before first paint, inlined in <head>. Without it the page renders in
// the device theme (and default accent) for a frame and then snaps to the
// stored choice.
export const THEME_BOOT_SCRIPT = `(function(){try{
var t=localStorage.getItem('${THEME_STORAGE_KEY}');
if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t);
var c=localStorage.getItem('${COLOR_THEME_STORAGE_KEY}');
if(c&&c!=='ultramarine')document.documentElement.setAttribute('data-color-theme',c);
}catch(e){}})()`

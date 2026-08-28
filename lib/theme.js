export const THEME_STORAGE_KEY = 'openly-theme'
export const THEME_OPTIONS = ['system', 'light', 'dark']

export function isThemePreference(value) {
  return THEME_OPTIONS.includes(value)
}

export const COLOR_THEME_STORAGE_KEY = 'openly-color-theme'

// Openly V2 uses crimson as the default accent. Other themes, including ultramarine, are explicit overrides.
export const COLOR_THEMES = [
  { value: 'crimson', label: 'عنّابي', swatch: '#7a2035' },
  { value: 'ultramarine', label: 'أزرق ملكي', swatch: '#16277a' },
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
if(c&&c!=='crimson')document.documentElement.setAttribute('data-color-theme',c);
}catch(e){}})()`

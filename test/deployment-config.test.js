import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile } from 'node:fs/promises'

const canonical = {
  siteUrl: 'https://openly.ink',
  supabaseUrl: 'https://egwhybfcnlzijomgeebj.supabase.co',
  publishableKey: 'sb_publishable_pZN6kVnQGZK3QwNdVmG7Ww_vqYqvO_X'
}

test('Vercel production config is pinned to the canonical public Supabase project', async () => {
  const config = JSON.parse(await readFile(new URL('../vercel.json', import.meta.url), 'utf8'))

  for (const env of [config.env, config.build?.env]) {
    assert.ok(env)
    assert.equal(env.NEXT_PUBLIC_SITE_URL, canonical.siteUrl)
    assert.equal(env.NEXT_PUBLIC_SUPABASE_URL, canonical.supabaseUrl)
    assert.equal(env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, canonical.publishableKey)
  }
})

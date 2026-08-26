import { cache } from 'react'
import { logError } from './logger.js'
import { createSupabaseServerClient } from './supabase.js'

function fail(event, error) {
  logError(event, error)
  throw error
}

export const getPublicProfilePage = cache(async code => {
  const supabase = await createSupabaseServerClient()
  const { data, error } = await supabase
    .from('profiles')
    .select('public_code,identity_color,created_at,status,bio')
    .eq('public_code', code)
    .maybeSingle()

  if (error) fail('metadata.profile', error)
  return data || null
})

export const getPublicPostPage = cache(async id => {
  const supabase = await createSupabaseServerClient()
  const { data: post, error } = await supabase
    .from('posts')
    .select('id,author_id,body,created_at,track_id')
    .eq('id', id)
    .is('deleted_at', null)
    .maybeSingle()

  if (error) fail('metadata.post', error)
  if (!post) return null

  const [authorResult, trackResult] = await Promise.all([
    supabase
      .from('profiles')
      .select('public_code,identity_color')
      .eq('id', post.author_id)
      .maybeSingle(),
    post.track_id
      ? supabase
          .from('music_tracks')
          .select('title,artist_name')
          .eq('id', post.track_id)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null })
  ])

  if (authorResult.error) fail('metadata.postAuthor', authorResult.error)
  if (trackResult.error) fail('metadata.postTrack', trackResult.error)

  return {
    ...post,
    authorCode: authorResult.data?.public_code || null,
    authorColor: authorResult.data?.identity_color || null,
    track: trackResult.data || null
  }
})

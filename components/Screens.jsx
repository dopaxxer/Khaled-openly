'use client'

import dynamic from 'next/dynamic'
import { NotFound } from './screens/NotFound'

// One route renders one screen, so nothing here belongs in the bundle a
// visitor downloads before they navigate. Every screen below is its own chunk:
// the home feed no longer ships the composer's mention search, the messaging
// poller, the music catalogue and the whole auth flow just to show posts.
// These stay server-rendered (next/dynamic prerenders by default), so a shared
// /u or /post link still arrives as HTML.
const lazy = load => dynamic(load)

const AuthScreen = lazy(() => import('./screens/AuthScreens').then(m => m.AuthScreen))
const ForgotPasswordScreen = lazy(() => import('./screens/AuthScreens').then(m => m.ForgotPasswordScreen))
const UpdatePasswordScreen = lazy(() => import('./screens/AuthScreens').then(m => m.UpdatePasswordScreen))
const SearchScreen = lazy(() => import('./screens/SearchScreen').then(m => m.SearchScreen))
const MeScreen = lazy(() => import('./screens/ProfileScreens').then(m => m.MeScreen))
const SettingsScreen = lazy(() => import('./screens/ProfileScreens').then(m => m.SettingsScreen))
const PrivacyScreen = lazy(() => import('./screens/ProfileScreens').then(m => m.PrivacyScreen))
const UserScreen = lazy(() => import('./screens/UserScreen').then(m => m.UserScreen))
const PostScreen = lazy(() => import('./screens/PostScreen').then(m => m.PostScreen))
const NotificationsScreen = lazy(() => import('./screens/FeedScreens').then(m => m.NotificationsScreen))
const BookmarksScreen = lazy(() => import('./screens/FeedScreens').then(m => m.BookmarksScreen))
const ReportScreen = lazy(() => import('./screens/ReportScreens').then(m => m.ReportScreen))
const AdminReportsScreen = lazy(() => import('./screens/ReportScreens').then(m => m.AdminReportsScreen))
const Composer = lazy(() => import('./Composer').then(m => m.Composer))
const MessageThread = lazy(() => import('./DirectMessages').then(m => m.MessageThread))
const MessagesInbox = lazy(() => import('./DirectMessages').then(m => m.MessagesInbox))
const MusicDiscovery = lazy(() => import('./MusicDiscovery').then(m => m.MusicDiscovery))
const MusicPreferences = lazy(() => import('./MusicPreferences').then(m => m.MusicPreferences))
const InterestDiscovery = lazy(() => import('./InterestDiscovery').then(m => m.InterestDiscovery))
const InterestPreferences = lazy(() => import('./InterestDiscovery').then(m => m.InterestPreferences))

export function ScreenRouter({ slug }) {
  const key = slug.join('/')
  if (key === 'login') return <AuthScreen mode="login" />
  if (key === 'register') return <AuthScreen mode="register" />
  if (key === 'forgot-password') return <ForgotPasswordScreen />
  if (key === 'auth/update-password') return <UpdatePasswordScreen />
  if (key === 'write') return <Composer />
  if (key === 'first-post') return <Composer firstPost />
  if (key === 'search') return <SearchScreen />
  if (key === 'discover') return <InterestDiscovery />
  if (key === 'interests') return <InterestPreferences />
  if (key === 'onboarding/interests') return <InterestPreferences onboarding />
  if (key === 'me') return <MeScreen />
  if (key === 'settings') return <SettingsScreen />
  if (key === 'notifications') return <NotificationsScreen />
  if (key === 'messages') return <MessagesInbox />
  if (key === 'bookmarks') return <BookmarksScreen />
  if (key === 'privacy') return <PrivacyScreen />
  if (key === 'music') return <MusicPreferences />
  if (key === 'discover/music') return <MusicDiscovery />
  if (key === 'admin/reports') return <AdminReportsScreen />
  if (slug[0] === 'messages' && slug[1]) return <MessageThread conversationId={slug[1]} />
  if (slug[0] === 'u' && slug[1]) return <UserScreen code={slug[1]} />
  if (slug[0] === 'post' && slug[1]) return <PostScreen id={slug[1]} />
  if (slug[0] === 'report' && slug[1] === 'post' && slug[2]) return <ReportScreen targetType="post" id={slug[2]} />
  if (slug[0] === 'report' && slug[1] === 'comment' && slug[2]) return <ReportScreen targetType="comment" id={slug[2]} />
  return <NotFound />
}

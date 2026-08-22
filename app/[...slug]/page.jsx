import { ScreenRouter } from '@/components/Screens'

export default async function Page({ params }) {
  const { slug = [] } = await params
  return <ScreenRouter slug={slug} />
}

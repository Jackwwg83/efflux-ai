import { redirect } from 'next/navigation'

export default function HomePage() {
  // 暂时重定向到登录页面
  redirect('/login')
}
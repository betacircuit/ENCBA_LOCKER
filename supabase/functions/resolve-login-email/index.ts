const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
}

type JsonRecord = Record<string, unknown>

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (request.method !== 'POST') {
    return json({ error: '허용되지 않은 요청입니다.' }, 405)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: '로그인 서버 설정이 완료되지 않았습니다.' }, 503)
  }

  const payload = await request.json().catch(() => null) as JsonRecord | null
  const email = typeof payload?.email === 'string' ? payload.email.trim().toLowerCase() : ''
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email) || email.length > 254) {
    return json({ login_email: email })
  }

  const headers = {
    Authorization: `Bearer ${serviceRoleKey}`,
    apikey: serviceRoleKey,
  }
  const profileResponse = await fetch(
    `${supabaseUrl}/rest/v1/profiles?email=eq.${encodeURIComponent(email)}&select=id,is_active&limit=1`,
    { headers },
  )
  if (!profileResponse.ok) {
    return json({ login_email: email })
  }
  const profiles = await profileResponse.json() as JsonRecord[]
  const profile = profiles[0]
  const userId = typeof profile?.id === 'string' ? profile.id : ''
  if (!userId) {
    return json({ login_email: email })
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}`, { headers })
  if (!userResponse.ok) {
    return json({ login_email: email })
  }
  const user = await userResponse.json() as JsonRecord
  const loginEmail = typeof user.email === 'string' ? user.email.toLowerCase() : email
  return json({ login_email: loginEmail })
})

function json(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

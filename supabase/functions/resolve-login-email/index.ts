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
  const rawIdentifier = typeof payload?.identifier === 'string'
    ? payload.identifier
    : typeof payload?.email === 'string' ? payload.email : ''
  const identifier = rawIdentifier.trim().toLowerCase()
  const isEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(identifier)
  const isEmailId = /^[a-z0-9._-]{1,64}$/iu.test(identifier)
  if ((!isEmail && !isEmailId) || identifier.length > 254) {
    return json({ login_email: '' })
  }

  const headers = {
    Authorization: `Bearer ${serviceRoleKey}`,
    apikey: serviceRoleKey,
  }
  const profileQuery = isEmail
    ? `email=eq.${encodeURIComponent(identifier)}`
    : `email=like.${encodeURIComponent(`${identifier}@*`)}`
  const profileResponse = await fetch(
    `${supabaseUrl}/rest/v1/profiles?${profileQuery}&select=id,email,is_active&limit=3`,
    { headers },
  )
  if (!profileResponse.ok) {
    return json({ login_email: isEmail ? identifier : '' })
  }
  const profiles = await profileResponse.json() as JsonRecord[]
  const matchingProfiles = profiles.filter((profile) =>
    profile.is_active === true &&
    typeof profile.email === 'string' &&
    isSnuSchoolEmail(profile.email),
  )
  const profile = matchingProfiles.length === 1 ? matchingProfiles[0] : null
  const userId = typeof profile?.id === 'string' ? profile.id : ''
  if (!userId) {
    return json({ login_email: isEmail ? identifier : '' })
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}`, { headers })
  if (!userResponse.ok) {
    return json({ login_email: isEmail ? identifier : '' })
  }
  const user = await userResponse.json() as JsonRecord
  const loginEmail = typeof user.email === 'string'
    ? user.email.toLowerCase()
    : isEmail ? identifier : ''
  return json({ login_email: loginEmail })
})

function json(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function isSnuSchoolEmail(email: string) {
  return /^[^@]+@([a-z0-9-]+\.)*snu\.ac\.kr$/i.test(email)
}

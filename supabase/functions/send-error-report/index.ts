const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (request.method !== 'POST') {
    return json({ error: '허용되지 않은 요청입니다.' }, 405)
  }

  const authorization = request.headers.get('Authorization')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const publishableKey = Deno.env.get('SUPABASE_ANON_KEY')
  const resendKey = Deno.env.get('RESEND_API_KEY')
  const sender = Deno.env.get('ERROR_REPORT_FROM')
  if (!authorization || !supabaseUrl || !publishableKey) {
    return json({ error: '로그인이 필요합니다.' }, 401)
  }
  if (!resendKey || !sender) {
    return json({ error: '메일 발송 설정이 완료되지 않았습니다.' }, 503)
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: authorization, apikey: publishableKey },
  })
  if (!userResponse.ok) {
    return json({ error: '유효한 계정이 아닙니다.' }, 401)
  }

  const payload = await request.json().catch(() => null)
  const body = typeof payload?.body === 'string' ? payload.body.trim() : ''
  if (body.length < 1 || body.length > 5000) {
    return json({ error: '오류 내용은 1자 이상 5,000자 이하로 입력해 주세요.' }, 400)
  }

  const mailResponse = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: sender,
      to: ['legojmon@snu.ac.kr'],
      subject: 'ENCBA LOCKER 오류 제보',
      text: body,
    }),
  })
  if (!mailResponse.ok) {
    return json({ error: '메일 발송에 실패했습니다.' }, 502)
  }
  return json({ sent: true })
})

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  })
}

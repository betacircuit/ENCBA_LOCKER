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

  const authorization = request.headers.get('Authorization')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const publishableKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!authorization || !supabaseUrl || !publishableKey) {
    return json({ error: 'Google 인증을 다시 진행해 주세요.' }, 401)
  }
  if (!serviceRoleKey) {
    return json({ error: '가입 서버 설정이 완료되지 않았습니다.' }, 503)
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: authorization, apikey: publishableKey },
  })
  if (!userResponse.ok) {
    return json({ error: 'Google 인증을 다시 진행해 주세요.' }, 401)
  }
  const user = await userResponse.json() as JsonRecord
  const userId = typeof user.id === 'string' ? user.id : ''
  const identities = Array.isArray(user.identities) ? user.identities : []
  const googleIdentity = identities.find((identity) => {
    return isRecord(identity) && identity.provider === 'google'
  })
  const identityData = isRecord(googleIdentity) && isRecord(googleIdentity.identity_data)
    ? googleIdentity.identity_data
    : null
  const schoolEmail = typeof identityData?.email === 'string'
    ? identityData.email.toLowerCase()
    : typeof user.email === 'string'
      ? user.email.toLowerCase()
      : ''
  if (!userId || !googleIdentity || !isSnuSchoolEmail(schoolEmail)) {
    return json({ error: '서울대학교 학교 계정으로 가입해 주세요.' }, 403)
  }
  const googleName = googleRealName(identityData)

  const payload = await request.json().catch(() => null)
  if (!isRecord(payload)) {
    return json({ error: '입력한 회원정보를 다시 확인해 주세요.' }, 400)
  }
  const name = stringValue(payload.requested_name).trim()
  const password = stringValue(payload.password)
  const studentYear = integerValue(payload.requested_student_year)
  const joinedYear = integerValue(payload.requested_joined_year)
  const phone = stringValue(payload.requested_phone).trim()
  const position = stringValue(payload.requested_position)
  const jerseyNumber = integerValue(payload.requested_jersey_number)
  const currentYear = Number(
    new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Seoul', year: 'numeric' })
      .format(new Date()),
  )
  if (
    name.length < 1 || name.length > 40 || name !== googleName || password.length < 8 ||
    studentYear === null || studentYear < 0 || studentYear > 99 ||
    joinedYear === null || joinedYear < 1977 || joinedYear > currentYear ||
    !/^010-\d{4}-\d{4}$/.test(phone) ||
    !['PG', 'SG', 'SF', 'PF', 'C', '미정'].includes(position) ||
    jerseyNumber === null || jerseyNumber < 0 || jerseyNumber > 99
  ) {
    return json({ error: '입력한 회원정보를 다시 확인해 주세요.' }, 400)
  }

  const adminHeaders = {
    Authorization: `Bearer ${serviceRoleKey}`,
    apikey: serviceRoleKey,
    'Content-Type': 'application/json',
  }
  const loginEmail = await internalEmail(name)
  const profileResponse = await fetch(
    `${supabaseUrl}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=name,phone`,
    { headers: adminHeaders },
  )
  if (!profileResponse.ok) {
    return json({ error: '가입 정보를 확인하지 못했습니다. 잠시 뒤 다시 시도해 주세요.' }, 502)
  }
  const profiles = await profileResponse.json() as JsonRecord[]
  const existingProfile = profiles[0]
  if (existingProfile && existingProfile.name !== name) {
    return json({ error: '이미 등록된 계정의 실명과 Google 실명이 다릅니다.' }, 409)
  }
  if (existingProfile && user.email === loginEmail) {
    return json({ error: '이미 등록된 계정입니다. 로그인 화면에서 로그인해 주세요.' }, 409)
  }

  if (!existingProfile) {
    // member_allowlist는 계정 목록이 아니라 ENCBA 구성원 자격 목록이다.
    // 실제 계정 존재 여부는 위 profiles로 판단하고, 여기서는 가입 자격과 이미
    // 다른 Google 사용자에게 연결됐는지만 확인한다.
    const allowlistResponse = await fetch(
      `${supabaseUrl}/rest/v1/member_allowlist?login_name=eq.${encodeURIComponent(name)}` +
        '&select=is_active,consumed_by',
      { headers: adminHeaders },
    )
    if (!allowlistResponse.ok) {
      return json({ error: '가입 자격을 확인하지 못했습니다. 잠시 뒤 다시 시도해 주세요.' }, 502)
    }
    const allowlistRows = await allowlistResponse.json() as JsonRecord[]
    const allowedMember = allowlistRows[0]
    if (!allowedMember || allowedMember.is_active !== true) {
      return json({ error: 'ENCBA 가입 명단에서 활성 부원 실명을 찾지 못했습니다.' }, 403)
    }
    if (
      typeof allowedMember.consumed_by === 'string' &&
      allowedMember.consumed_by !== userId
    ) {
      return json({ error: '이미 등록된 계정입니다. 로그인 화면에서 로그인해 주세요.' }, 409)
    }
  }

  const passwordResponse = await updateAuthUser(
    supabaseUrl,
    userId,
    adminHeaders,
    { password },
  )
  if (!passwordResponse.ok && !(await isSamePassword(passwordResponse))) {
    return json({ error: '비밀번호를 설정하지 못했습니다. 다른 비밀번호로 다시 시도해 주세요.' }, 422)
  }

  if (!existingProfile) {
    const registrationResponse = await fetch(
      `${supabaseUrl}/rest/v1/rpc/complete_google_registration`,
      {
        method: 'POST',
        headers: {
          Authorization: authorization,
          apikey: publishableKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          requested_name: name,
          requested_student_year: studentYear,
          requested_joined_year: joinedYear,
          requested_phone: phone,
          requested_position: position,
          requested_jersey_number: jerseyNumber,
        }),
      },
    )
    if (!registrationResponse.ok) {
      const errorText = await registrationResponse.text()
      if (errorText.includes('ENCBA_MEMBER_NOT_ALLOWLISTED')) {
        const latestAllowlist = await fetch(
          `${supabaseUrl}/rest/v1/member_allowlist?login_name=eq.${encodeURIComponent(name)}` +
            '&select=is_active,consumed_by',
          { headers: adminHeaders },
        ).then((response) => response.ok ? response.json() : []).catch(() => []) as JsonRecord[]
        if (
          typeof latestAllowlist[0]?.consumed_by === 'string' &&
          latestAllowlist[0]?.consumed_by !== userId
        ) {
          return json({ error: '이미 등록된 계정입니다. 로그인 화면에서 로그인해 주세요.' }, 409)
        }
        return json({ error: 'ENCBA 가입 명단에서 활성 부원 실명을 찾지 못했습니다.' }, 403)
      }
      if (errorText.includes('ENCBA_GOOGLE_REGISTRATION_INVALID')) {
        return json({ error: '입력한 회원정보를 다시 확인해 주세요.' }, 400)
      }
      return json({ error: '회원정보를 저장하지 못했습니다. 잠시 뒤 다시 시도해 주세요.' }, 502)
    }
  } else if (existingProfile.phone !== phone) {
    // 프로필 생성 뒤 응답 확인이나 이메일 전환만 실패한 요청은 같은 사용자의
    // 온보딩 재시도다. 전화번호까지 직전 입력값으로 복구하고 나머지 단계를 잇는다.
    const phoneRecoveryResponse = await fetch(
      `${supabaseUrl}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}`,
      {
        method: 'PATCH',
        headers: adminHeaders,
        body: JSON.stringify({ phone }),
      },
    )
    if (!phoneRecoveryResponse.ok) {
      return json({ error: '전화번호를 저장하지 못했습니다. 다시 시도해 주세요.' }, 502)
    }
  }

  const savedProfileResponse = await fetch(
    `${supabaseUrl}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=phone`,
    { headers: adminHeaders },
  )
  const savedProfiles = savedProfileResponse.ok
    ? await savedProfileResponse.json() as JsonRecord[]
    : []
  if (savedProfiles[0]?.phone !== phone) {
    return json({ error: '전화번호 저장을 확인하지 못했습니다. 다시 시도해 주세요.' }, 502)
  }

  if (user.email !== loginEmail) {
    const emailResponse = await updateAuthUser(
      supabaseUrl,
      userId,
      adminHeaders,
      { email: loginEmail, email_confirm: true },
    )
    if (!emailResponse.ok) {
      const errorText = await emailResponse.text()
      if (errorText.includes('already')) {
        return json({ error: '이미 사용 중인 실명 아이디입니다.' }, 409)
      }
      return json({ error: '실명 로그인 아이디를 만들지 못했습니다. 잠시 뒤 다시 시도해 주세요.' }, 502)
    }
  }

  return json({ completed: true, login_name: name, phone })
})

function updateAuthUser(
  supabaseUrl: string,
  userId: string,
  headers: Record<string, string>,
  body: JsonRecord,
) {
  return fetch(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    method: 'PUT',
    headers,
    body: JSON.stringify(body),
  })
}

async function isSamePassword(response: Response) {
  const body = await response.clone().json().catch(() => null)
  if (!isRecord(body)) return false
  const code = stringValue(body.code || body.error_code)
  const message = stringValue(body.message || body.msg).toLowerCase()
  return code === 'same_password' || message.includes('different from the old password')
}

async function internalEmail(name: string) {
  // 이메일 로컬 파트 제한을 넘지 않는 고정 길이 식별자다. 기존 일반 가입의
  // Dart 변환 규칙과 반드시 같아야 하며, 사용자 실명 유일성은 명단 제약으로 막는다.
  const bytes = new TextEncoder().encode(name.trim())
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  const encoded = Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('')
  return `${encoded}@members.encba.local`
}

function googleRealName(identityData: JsonRecord | null) {
  const raw = stringValue(identityData?.full_name || identityData?.name)
  return raw.replaceAll('\u00ad', '').split(/\s*\/\s*/u)[0].trim()
}

function isSnuSchoolEmail(email: string) {
  return /^[^@]+@([a-z0-9-]+\.)*snu\.ac\.kr$/i.test(email)
}

function integerValue(value: unknown) {
  return typeof value === 'number' && Number.isInteger(value) ? value : null
}

function stringValue(value: unknown) {
  return typeof value === 'string' ? value : ''
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function json(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  })
}

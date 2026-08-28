// AI 채우기
//
// 관리자가 "이번 학기 동안 정기훈련 채워줘"처럼 한 줄을 적으면 모델이
// 새 일정 또는 새 공지의 입력값을 채워 준다. API 키는 이 함수의 환경변수에만
// 두고, 앱(브라우저)에는 절대 내려보내지 않는다.
//
// 필요한 환경변수
//   GEMINI_API_KEY - Google AI Studio(aistudio.google.com/apikey)에서 발급한 키
//   GEMINI_MODEL   - (선택) 쉼표로 여러 개를 적으면 앞에서부터 시도한다.
//                    기본값은 아래 defaultModels.
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY - 호출자 권한 확인용

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, apikey, content-type, x-client-info',
}

// Gemini Interactions API. 예전 generateContent 대신 이 엔드포인트를 쓴다.
const geminiEndpoint =
  'https://generativelanguage.googleapis.com/v1beta/interactions'
/// 무료 티어에서 쓸 수 있는 모델을 성능 순으로 늘어놓는다.
///
/// 무료 티어는 붐빌 때 500 "experiencing high demand"를 자주 뱉는다. 한
/// 모델만 붙들고 있으면 그 시간대에는 기능이 통째로 죽으므로, 막히면
/// 다음 모델로 자동으로 내려간다.
const defaultModels = [
  'gemini-3.7-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash',
  'gemini-2.5-flash',
]

/// 다음 모델로 넘어가 볼 만한 상태 코드. 429는 한도, 5xx는 상류 혼잡,
/// 404는 그 계정에서 못 쓰는 모델이라는 뜻이다.
const retryableStatuses = new Set([404, 429, 500, 502, 503, 504])
const maxPromptLength = 2000
const maxEvents = 60

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
  const apiKey = Deno.env.get('GEMINI_API_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: '서버 설정이 완료되지 않았습니다.' }, 503)
  }
  if (!apiKey) {
    return json(
      { error: 'AI 채우기가 아직 설정되지 않았습니다. 관리자에게 문의해 주세요.' },
      503,
    )
  }

  const adminId = await authenticateAdmin(request, supabaseUrl, serviceRoleKey)
  if (adminId === null) {
    return json({ error: '일정·공지 관리자만 사용할 수 있습니다.' }, 401)
  }

  const payload = await request.json().catch(() => null)
  if (!isRecord(payload)) return json({ error: '요청 형식이 올바르지 않습니다.' }, 400)

  const kind = payload.kind
  if (kind !== 'events' && kind !== 'announcement') {
    return json({ error: '지원하지 않는 채우기 종류입니다.' }, 400)
  }
  const prompt = typeof payload.prompt === 'string' ? payload.prompt.trim() : ''
  if (prompt.length < 2 || prompt.length > maxPromptLength) {
    return json(
      { error: `프롬프트는 2자 이상 ${maxPromptLength}자 이하로 적어 주세요.` },
      400,
    )
  }
  const context = isRecord(payload.context) ? payload.context : {}
  const schema = kind === 'events' ? eventSchema() : announcementSchema()

  const configured = (Deno.env.get('GEMINI_MODEL') ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0)
  const candidates = configured.length > 0 ? configured : defaultModels

  const body = {
    system_instruction: [
      kind === 'events' ? eventSystemPrompt() : announcementSystemPrompt(),
      '',
      '스키마를 정확히 따르는 JSON 객체 하나만 출력합니다.',
      '설명, 인사말, 코드펜스는 붙이지 않습니다.',
    ].join('\n'),
    input: [
      `오늘은 ${todayInKorea()} (한국 시간) 입니다.`,
      `참고 정보: ${JSON.stringify(context)}`,
      '',
      '요청:',
      prompt,
    ].join('\n'),
    // 스키마를 강제해도 드물게 군더더기가 섞여 오므로 parseJsonPayload가
    // 앞뒤를 걷어내며 방어적으로 읽는다.
    response_format: {
      type: 'text',
      mime_type: 'application/json',
      schema,
    },
    // 대화를 서버에 남길 이유가 없다. 한 번 부르고 끝난다.
    store: false,
  }

  // 붐비는 모델은 건너뛰고 다음 후보로 내려간다.
  let response: Response | null = null
  let usedModel = candidates[0]
  let lastStatus = 0
  let lastDetail = ''
  for (const model of candidates) {
    const attempt = await fetch(geminiEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify({ model, ...body }),
    })
    if (attempt.ok) {
      response = attempt
      usedModel = model
      break
    }
    lastStatus = attempt.status
    lastDetail = await attempt.text().catch(() => '')
    console.error('gemini request failed', model, attempt.status, lastDetail)
    // 요청이 잘못됐거나 키 문제라면 모델을 바꿔도 결과는 같다.
    if (!retryableStatuses.has(attempt.status)) break
  }

  if (response === null) {
    if (lastStatus === 429) {
      return json(
        { error: 'AI 무료 사용량을 넘었습니다. 잠시 뒤 다시 시도해 주세요.' },
        502,
      )
    }
    if (retryableStatuses.has(lastStatus)) {
      return json(
        {
          error:
            'AI가 지금 붐빕니다. 무료 모델을 차례로 시도했지만 모두 응답하지 못했어요. ' +
            '잠시 뒤 다시 눌러 주세요.',
        },
        502,
      )
    }
    // 이 함수는 관리자만 부를 수 있다. 원인을 감추면 무엇을 고쳐야 할지
    // 알 수 없어서, 서버가 준 사유를 그대로(길이만 잘라) 넘긴다.
    return json(
      {
        error: `AI가 응답하지 못했습니다. (${lastStatus}) ` +
          `${upstreamReason(lastDetail)}`,
      },
      502,
    )
  }

  // Google은 본문을 그냥 객체로 줄 때도 있고 한 칸짜리 배열로 감싸 줄 때도
  // 있다(오류 응답이 특히 그렇다). 둘 다 받아 준다.
  const completion = unwrapBody(await response.json().catch(() => null))
  if (!isRecord(completion)) {
    return json({ error: 'AI 응답을 이해하지 못했습니다.' }, 502)
  }
  if (isRecord(completion.error)) {
    console.error('gemini upstream error', completion.error)
    return json(
      {
        error: `AI가 응답하지 못했습니다. ${upstreamReason(
          JSON.stringify(completion),
        )}`,
      },
      502,
    )
  }
  // 실패한 상호작용도 HTTP 200으로 온다. status를 먼저 본다.
  if (completion.status === 'failed') {
    console.error('gemini interaction failed', completion.error)
    return json(
      {
        error: `AI가 응답하지 못했습니다. ${upstreamReason(
          JSON.stringify(completion.error ?? ''),
        )}`,
      },
      502,
    )
  }

  const text = firstMessageText(completion)
  if (text === null) return json({ error: 'AI 응답이 비어 있습니다.' }, 502)

  const parsed = parseJsonPayload(text)
  if (parsed === null) return json({ error: 'AI 응답을 읽지 못했습니다.' }, 502)

  if (kind === 'events' && Array.isArray(parsed.events)) {
    parsed.events = parsed.events.slice(0, maxEvents)
  }
  return json({ result: parsed, model: usedModel })
})

function eventSystemPrompt(): string {
  return [
    '당신은 서울대학교 농구 동아리 ENCBA의 일정 담당자를 돕는 도우미입니다.',
    '사용자의 요청을 읽고 등록할 일정 목록을 JSON으로 만듭니다.',
    '',
    '규칙:',
    '- "이번 학기 동안", "매주"처럼 반복을 뜻하면 해당 기간의 날짜를 모두 펼쳐서 각각 하나의 일정으로 만듭니다.',
    '- 학기는 1학기 3월 1일~6월 15일, 여름학기 6월 16일~8월 31일, 2학기 9월 1일~12월 14일, 겨울학기 12월 15일~다음 해 2월 말입니다.',
    '- 일정 유형(kind)은 다음 중 하나입니다: training(훈련), morning(아침농구), freeOpen(자유개방), pickup(픽업게임), ibDivision1(IB 1부), ibDivision2(IB 2부), scrimmage(연습경기), threeWay(3자 연습경기), external(외부 대회).',
    '- 동아리에서 줄여 부르는 말을 알아들어야 합니다:',
    '  · "아농" = 아침농구 → morning',
    '  · "자개" = 자유개방 → freeOpen',
    '  · "연겜", "연경" = 연습경기 → scrimmage (상대가 둘이면 threeWay)',
    '  · "픽업", "픽겜" = 픽업게임 → pickup',
    '  · "정훈", "훈련" = 정기훈련 → training',
    '  · "외대", "외부대회" → external',
    '  · "IB 1부/2부" → ibDivision1 / ibDivision2',
    '- 상대 팀 이름이 함께 나오면(예: "호바스랑", "스티즈와") 연습경기로 봅니다.',
    '- IB 경기의 시작 시간은 1경기 13:00, 2경기 14:10, 3경기 15:20이며 장소는 항상 "71동 종합체육관"입니다.',
    '- 장소는 "71동 종합체육관", "71-1동 신체육관", "900동 기숙사체육관" 중에서 고르고, 셋 다 아니면 들은 그대로 적습니다.',
    '- 공개 대상(targetTeam)은 전체 / ENCBA / BEN / 신입생 중 하나입니다.',
    '- 날짜와 시간은 한국 시간 기준 "YYYY-MM-DDTHH:mm" 형식으로만 씁니다.',
    '- 요청에 없어서 지어내야 하는 값은 절대 채우지 말고 questions 목록에 물어볼 내용을 담습니다.',
    '- questions의 field는 kind, title, start, end, place, targetTeam, memo 중 하나입니다.',
    '- 과거 날짜는 만들지 않습니다.',
  ].join('\n')
}

function announcementSystemPrompt(): string {
  return [
    '당신은 서울대학교 농구 동아리 ENCBA의 공지 작성자를 돕는 도우미입니다.',
    '사용자의 요청을 읽고 공지 초안을 JSON으로 만듭니다.',
    '',
    '규칙:',
    '- 제목은 한 줄로 간결하게, 본문은 부원이 바로 행동할 수 있도록 일시·장소·준비물을 문단으로 적습니다.',
    '- 문체는 정중한 한국어 존댓말입니다.',
    '- 투표가 필요해 보일 때만 poll을 채우고, 그렇지 않으면 poll의 question과 options를 비웁니다.',
    '- 요청에 없어서 지어내야 하는 값은 채우지 말고 questions 목록에 물어볼 내용을 담습니다.',
    '- questions의 field는 title, body, poll, pinned 중 하나입니다.',
  ].join('\n')
}

function eventSchema(): JsonRecord {
  return {
    type: 'object',
    required: ['events', 'questions', 'summary'],
    properties: {
      summary: { type: 'string', description: '무엇을 만들었는지 한 문장 요약' },
      events: {
        type: 'array',
        items: {
          type: 'object',
                required: ['kind', 'title', 'start', 'end', 'place', 'targetTeam', 'memo'],
          properties: {
            kind: {
              type: 'string',
              enum: [
                'training',
                'morning',
                'freeOpen',
                'pickup',
                'ibDivision1',
                'ibDivision2',
                'scrimmage',
                'threeWay',
                'external',
              ],
            },
            title: { type: 'string' },
            start: { type: 'string', description: 'YYYY-MM-DDTHH:mm' },
            end: { type: 'string', description: 'YYYY-MM-DDTHH:mm' },
            place: { type: 'string' },
            targetTeam: {
              type: 'string',
              enum: ['전체', 'ENCBA', 'BEN', '신입생'],
            },
            memo: { type: 'string' },
          },
        },
      },
      questions: {
        type: 'array',
        items: {
          type: 'object',
                required: ['field', 'question'],
          properties: {
            field: {
              type: 'string',
              enum: ['kind', 'title', 'start', 'end', 'place', 'targetTeam', 'memo'],
            },
            question: { type: 'string' },
          },
        },
      },
    },
  }
}

function announcementSchema(): JsonRecord {
  return {
    type: 'object',
    required: ['title', 'body', 'pinned', 'poll', 'questions', 'summary'],
    properties: {
      summary: { type: 'string' },
      title: { type: 'string' },
      body: { type: 'string' },
      pinned: { type: 'boolean' },
      poll: {
        type: 'object',
            required: ['question', 'options'],
        properties: {
          question: { type: 'string' },
          options: { type: 'array', items: { type: 'string' } },
        },
      },
      questions: {
        type: 'array',
        items: {
          type: 'object',
                required: ['field', 'question'],
          properties: {
            field: {
              type: 'string',
              enum: ['title', 'body', 'poll', 'pinned'],
            },
            question: { type: 'string' },
          },
        },
      },
    },
  }
}

/// Interactions API 응답에서 모델이 쓴 본문을 꺼낸다. 답은 steps 배열의
/// model_output 안에 텍스트 블록으로 들어 있고 여러 조각으로 쪼개져 올 수
/// 있어 이어 붙인다. 사고 과정 블록은 type이 text가 아니라 자연히 걸러진다.
function firstMessageText(completion: JsonRecord): string | null {
  const steps = completion.steps
  if (!Array.isArray(steps)) return null
  let joined = ''
  for (const step of steps) {
    if (!isRecord(step) || step.type !== 'model_output') continue
    const content = step.content
    if (!Array.isArray(content)) continue
    for (const block of content) {
      if (
        isRecord(block) &&
        block.type === 'text' &&
        typeof block.text === 'string'
      ) {
        joined += block.text
      }
    }
  }
  return joined.trim().length > 0 ? joined : null
}

/// 코드펜스나 앞뒤 설명이 섞여 와도 JSON 객체만 골라 읽는다.
function parseJsonPayload(text: string): JsonRecord | null {
  const candidates = [text]
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/u)
  if (fenced?.[1]) candidates.push(fenced[1])
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start >= 0 && end > start) candidates.push(text.slice(start, end + 1))

  for (const candidate of candidates) {
    try {
      const parsed = JSON.parse(candidate.trim())
      if (isRecord(parsed)) return parsed
    } catch (_error) {
      // 다음 후보를 시도한다.
    }
  }
  return null
}

function todayInKorea(): string {
  const now = new Date(Date.now() + 9 * 60 * 60 * 1000)
  return now.toISOString().slice(0, 10)
}

async function authenticateAdmin(
  request: Request,
  supabaseUrl: string,
  serviceRoleKey: string,
): Promise<string | null> {
  const authorization = request.headers.get('Authorization')
  if (!authorization?.startsWith('Bearer ')) return null
  const token = authorization.slice('Bearer '.length).trim()
  if (!token) return null
  const base = supabaseUrl.replace(/\/$/u, '')
  const response = await fetch(`${base}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: serviceRoleKey },
  })
  if (!response.ok) return null
  const user = await response.json().catch(() => null)
  if (!isRecord(user) || typeof user.id !== 'string') return null

  const query = new URLSearchParams({
    select: 'id,is_admin,is_schedule_manager,leadership_role',
    id: `eq.${user.id}`,
    is_active: 'eq.true',
    limit: '1',
  })
  const profileResponse = await fetch(`${base}/rest/v1/profiles?${query}`, {
    headers: {
      Authorization: `Bearer ${serviceRoleKey}`,
      apikey: serviceRoleKey,
    },
  })
  if (!profileResponse.ok) return null
  const rows = await profileResponse.json().catch(() => null)
  if (!Array.isArray(rows) || !isRecord(rows[0])) return null
  const profile = rows[0]
  if (profile.is_admin === true || profile.is_schedule_manager === true) {
    return user.id
  }
  const role = typeof profile.leadership_role === 'string'
    ? profile.leadership_role
    : ''
  return role === 'admin' || role === 'captain' ? user.id : null
}

/// 한 칸짜리 배열로 감싸 온 본문을 벗겨 낸다.
function unwrapBody(value: unknown): unknown {
  if (Array.isArray(value) && value.length > 0) return value[0]
  return value
}

/// 상류(Google) 오류 본문에서 사람이 읽을 사유만 짧게 뽑는다.
function upstreamReason(detail: string): string {
  if (!detail) return ''
  try {
    const parsed = unwrapBody(JSON.parse(detail))
    const message = isRecord(parsed) && isRecord(parsed.error)
      ? parsed.error.message
      : null
    if (typeof message === 'string' && message.length > 0) {
      return message.slice(0, 300)
    }
  } catch (_error) {
    // JSON이 아니면 원문을 그대로 줄여 쓴다.
  }
  return detail.slice(0, 300)
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function json(body: JsonRecord, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

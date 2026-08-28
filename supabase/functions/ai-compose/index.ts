// AI 채우기
//
// 관리자가 "이번 학기 동안 정기훈련 채워줘"처럼 한 줄을 적으면 모델이
// 새 일정 또는 새 공지의 입력값을 채워 준다. API 키는 이 함수의 환경변수에만
// 두고, 앱(브라우저)에는 절대 내려보내지 않는다.
//
// 필요한 환경변수
//   GROQ_API_KEY - console.groq.com 에서 발급한 키
//   GROQ_MODEL   - (선택) 쉼표로 여러 개를 적으면 앞에서부터 시도한다.
//                  기본값은 아래 defaultModels.
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY - 호출자 권한 확인용

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, apikey, content-type, x-client-info',
}

// Groq은 OpenAI 호환 chat/completions 형식을 쓴다.
const groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions'

/// 쓸 수 있는 모델을 성능 순으로 늘어놓는다.
///
/// 무료 한도는 붐빌 때 429·5xx를 자주 뱉는다. 한 모델만 붙들고 있으면 그
/// 시간대에 기능이 통째로 죽으므로, 막히면 다음 모델로 자동으로 내려간다.
/// "9월 매주 화요일" 같은 반복 요청을 실제로 돌려 보고 정한 순서다.
/// gpt-oss-120b와 compound-mini는 다섯 번의 화요일을 정확히 펼쳤고,
/// qwen3.8-27b는 마지막 주를 빠뜨렸다. gpt-oss-20b는 요일을 틀리거나
/// JSON 생성 자체에 실패해서 뺐다.
const defaultModels = [
  'openai/gpt-oss-120b',
  'groq/compound-mini',
  'qwen/qwen3.8-27b',
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
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: '서버 설정이 완료되지 않았습니다.' }, 503)
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

  // 키는 반드시 환경변수에서만 읽는다. 소스에 적어 두면 이 저장소가
  // 공개돼 있어 키가 그대로 새어 나간다.
  const apiKey = Deno.env.get('GROQ_API_KEY')
  if (!apiKey) {
    return json(
      { error: 'AI 채우기가 아직 설정되지 않았습니다. 관리자에게 문의해 주세요.' },
      503,
    )
  }
  const configured = (Deno.env.get('GROQ_MODEL') ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0)
  const candidates = configured.length > 0 ? configured : defaultModels

  const systemInstruction = [
    kind === 'events' ? eventSystemPrompt() : announcementSystemPrompt(),
    '',
    '스키마를 정확히 따르는 JSON 객체 하나만 출력합니다.',
    'JSON 객체는 다음 스키마를 따라야 합니다:',
    JSON.stringify(schema, null, 2),
    '설명, 인사말, 코드펜스는 붙이지 않습니다.',
  ].join('\n')

  const userInput = [
    `오늘은 ${todayInKorea()} (한국 시간) 입니다.`,
    `참고 정보: ${JSON.stringify(context)}`,
    '',
    '요청:',
    prompt,
  ].join('\n')

  let response: Response | null = null
  let usedModel = candidates[0]
  let lastStatus = 0
  let lastDetail = ''

  for (const model of candidates) {
    const attempt = await fetch(groqEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: model,
        messages: [
          { role: 'system', content: systemInstruction },
          { role: 'user', content: userInput }
        ],
        response_format: { type: 'json_object' },
      }),
    })

    if (attempt.ok) {
      response = attempt
      usedModel = model
      break
    }
    lastStatus = attempt.status
    lastDetail = await attempt.text().catch(() => '')
    console.error('groq request failed', model, attempt.status, lastDetail)
    // 스키마를 못 지켜 400이 나는 건 그 모델의 사정이다. 요청은 멀쩡하니
    // 다음 모델에서는 될 수 있다.
    const shouldTryNext =
      retryableStatuses.has(attempt.status) || isJsonGenerationFailure(lastDetail)
    if (!shouldTryNext) break
  }

  if (response === null) {
    if (isJsonGenerationFailure(lastDetail)) {
      return json(
        {
          error: 'AI가 형식에 맞는 답을 만들지 못했습니다. 요청을 조금 더 또렷하게 적어 주세요.',
        },
        502,
      )
    }
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

  // 오류 응답을 한 칸짜리 배열로 감싸 보내는 제공자가 있어 둘 다 받아 준다.
  const completion = unwrapBody(await response.json().catch(() => null))
  if (!isRecord(completion)) {
    return json({ error: 'AI 응답을 이해하지 못했습니다.' }, 502)
  }
  if (isRecord(completion.error)) {
    console.error('ai upstream error', completion.error)
    return json(
      {
        error: `AI가 응답하지 못했습니다. ${upstreamReason(
          JSON.stringify(completion),
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
    '- 사용자가 "3시~5시" 등 새벽 시간(00:00~07:00)을 입력한 경우 자동으로 오후 시간(15:00~19:00)으로 처리하세요.',
    '- 요청에 없어서 지어내야 하는 값은 빈 문자열("")로 남겨 두고 questions 목록에 물어볼 내용을 담습니다. 절대로 일정을 누락하지 말고, 알 수 있는 최대한의 정보로 events를 채워야 합니다.',
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
    '- 문체는 정중하고 아주 간결한 한국어 존댓말입니다. 군더더기 인사말은 생략하고 핵심만 짧게 씁니다.',
    '- 투표가 필요해 보일 때만 poll을 채우고, 그렇지 않으면 poll의 question과 options를 비웁니다.',
    '- 요청에 없어서 지어내야 하는 값은 빈 문자열("")로 남겨 두고 questions 목록에 물어볼 내용을 담습니다. 공지 초안 작성을 포기하지 말고 최대한 작성해야 합니다.',
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

/// OpenAI/Groq Chat Completion API 응답에서 텍스트를 꺼낸다.
function firstMessageText(completion: JsonRecord): string | null {
  const choices = completion.choices
  if (!Array.isArray(choices) || choices.length === 0) return null
  const firstChoice = choices[0]
  if (!isRecord(firstChoice)) return null
  const message = firstChoice.message
  if (!isRecord(message)) return null
  const content = message.content
  return typeof content === 'string' && content.trim().length > 0 ? content : null
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

/// Groq이 "Failed to generate JSON"으로 돌려보낸 경우인지 본다. 요청이
/// 잘못된 게 아니라 그 모델이 스키마를 못 지킨 것이라 다음 모델로 넘긴다.
function isJsonGenerationFailure(detail: string): boolean {
  if (!detail) return false
  return detail.includes('json_validate_failed') ||
    detail.includes('Failed to generate JSON')
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

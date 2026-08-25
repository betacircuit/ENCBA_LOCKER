import { GoogleAuth } from 'npm:google-auth-library@11.0.2'

type JsonRecord = Record<string, unknown>
type Category = 'announcements' | 'events'

type PushSubscription = {
  id: number
  profileId: string
  token: string
  categories: string[]
}

type ProfileAccess = {
  isAdmin: boolean
  teams: Set<string>
}

type EventRow = {
  id: string
  title: string
  responseDeadline: string
  startsAt: string
  targetTeam: string
  visibility: string
}

type PushCandidate = {
  category: Category
  id: string
  title: string
  body: string
  path: string
  dedupeKey: string
  event?: EventRow
}

type DispatchTask = {
  candidate: PushCandidate
  subscription: PushSubscription
}

type AdminContext = {
  supabaseUrl: string
  headers: Record<string, string>
}

type FcmResult = {
  ok: boolean
  unregistered: boolean
}

const firebaseMessagingScope = 'https://www.googleapis.com/auth/firebase.messaging'
const recentAnnouncementWindowMs = 24 * 60 * 60 * 1000
const attendanceReminderLeadMs = 3 * 60 * 60 * 1000
const dispatchConcurrency = 10

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405, { Allow: 'POST' })
  }

  const webhookSecret = Deno.env.get('PUSH_WEBHOOK_SECRET')
  if (!webhookSecret) {
    return json({ error: 'Server configuration incomplete' }, 503)
  }
  // 웹훅·크론은 공유 시크릿으로, 앱에서 온 응답 독촉 요청은 호출자 JWT로
  // 신뢰를 확인한다. 두 경로가 섞이지 않게 아래에서 kind별로 강제한다.
  const viaWebhook = request.headers.get('x-push-secret') === webhookSecret

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const fcmProjectId = Deno.env.get('FCM_PROJECT_ID')
  const serviceAccountText = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')
  if (!supabaseUrl || !serviceRoleKey || !fcmProjectId || !serviceAccountText) {
    return json({ error: 'Server configuration incomplete' }, 503)
  }

  const rawBody = await request.text()
  const payloadResult = parsePayload(rawBody)
  if (!payloadResult.ok) {
    return json({ error: 'Invalid JSON body' }, 400)
  }

  const invocation = classifyInvocation(payloadResult.value)

  if (viaWebhook) {
    if (invocation.kind === 'invalid') {
      return json({ error: 'Unsupported push invocation' }, 400)
    }
    if (invocation.kind === 'reminder') {
      return json({ error: 'Reminder requires an authenticated admin' }, 403)
    }
  } else {
    if (invocation.kind !== 'reminder') {
      return json({ error: 'Unauthorized' }, 401)
    }
    const adminProfileId = await authenticateAdmin(request, supabaseUrl, serviceRoleKey)
    if (adminProfileId === null) {
      return json({ error: 'Unauthorized' }, 401)
    }
  }

  const admin: AdminContext = {
    supabaseUrl: supabaseUrl.replace(/\/$/u, ''),
    headers: {
      Authorization: `Bearer ${serviceRoleKey}`,
      apikey: serviceRoleKey,
      'Content-Type': 'application/json',
    },
  }

  try {
    const candidates = invocation.kind === 'announcement'
      ? announcementWebhookCandidates(invocation.record)
      : invocation.kind === 'reminder'
        ? await reminderCandidates(admin, invocation.eventId)
        : await cronCandidates(admin)

    if (candidates === null) {
      return json({ error: 'Invalid announcement webhook' }, 400)
    }
    if (candidates.length === 0) {
      return json({ ok: true, candidates: 0, targets: 0, sent: 0, skipped: 0, failed: 0 })
    }

    const subscriptions = await loadSubscriptions(admin)
    if (subscriptions.length === 0) {
      return json({
        ok: true,
        candidates: candidates.length,
        targets: 0,
        sent: 0,
        skipped: 0,
        failed: 0,
      })
    }

    const tasks = await buildDispatchTasks(admin, candidates, subscriptions)
    if (tasks.length === 0) {
      return json({
        ok: true,
        candidates: candidates.length,
        targets: 0,
        sent: 0,
        skipped: 0,
        failed: 0,
      })
    }

    const serviceAccount = parseServiceAccount(serviceAccountText)
    if (!serviceAccount) {
      return json({ error: 'Server configuration incomplete' }, 503)
    }
    const accessToken = await firebaseAccessToken(serviceAccount)
    if (!accessToken) {
      return json({ error: 'Push provider authentication failed' }, 502)
    }

    const results = await mapConcurrent(
      tasks,
      dispatchConcurrency,
      (task) => dispatchOne(admin, fcmProjectId, accessToken, task),
    )
    const sent = results.filter((result) => result === 'sent').length
    const skipped = results.filter((result) => result === 'skipped').length
    const failed = results.filter((result) => result === 'failed').length

    return json({
      ok: failed === 0,
      candidates: candidates.length,
      targets: tasks.length,
      sent,
      skipped,
      failed,
    }, failed === 0 ? 200 : 207)
  } catch {
    return json({ error: 'Push dispatch failed' }, 502)
  }
})

function parsePayload(rawBody: string): { ok: true; value: unknown } | { ok: false } {
  if (!rawBody.trim()) return { ok: true, value: null }
  try {
    return { ok: true, value: JSON.parse(rawBody) }
  } catch {
    return { ok: false }
  }
}

function classifyInvocation(payload: unknown):
  | { kind: 'cron' }
  | { kind: 'announcement'; record: JsonRecord }
  | { kind: 'reminder'; eventId: string }
  | { kind: 'invalid' } {
  if (payload === null) return { kind: 'cron' }
  if (!isRecord(payload)) return { kind: 'invalid' }
  if (payload.kind === 'response_reminder') {
    const eventId = stringValue(payload.event_id)
    return eventId ? { kind: 'reminder', eventId } : { kind: 'invalid' }
  }
  if (Object.keys(payload).length === 0 || payload.type === 'cron' || payload.source === 'cron') {
    return { kind: 'cron' }
  }
  if (payload.table === 'announcements' && isRecord(payload.record)) {
    return { kind: 'announcement', record: payload.record }
  }
  return { kind: 'invalid' }
}

/// 앱에서 온 요청이 관리자·주장(canAdminister와 같은 기준)인지 확인한다.
/// 성공하면 프로필 ID를, 아니면 null을 돌려준다.
async function authenticateAdmin(
  request: Request,
  supabaseUrl: string,
  serviceRoleKey: string,
): Promise<string | null> {
  const authorization = request.headers.get('Authorization')
  if (!authorization?.startsWith('Bearer ')) return null
  const token = authorization.slice('Bearer '.length).trim()
  if (!token) return null
  const response = await fetch(`${supabaseUrl.replace(/\/$/u, '')}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: serviceRoleKey },
  })
  if (!response.ok) return null
  const user = await response.json().catch(() => null)
  if (!isRecord(user) || typeof user.id !== 'string') return null

  const profileRows = await getRowsWith(supabaseUrl, serviceRoleKey, 'profiles', {
    select: 'id,is_admin,leadership_role',
    id: `eq.${user.id}`,
    is_active: 'eq.true',
    limit: '1',
  })
  const profile = profileRows[0]
  if (!profile) return null
  if (profile.is_admin === true) return user.id
  const role = stringValue(profile.leadership_role)
  return role === 'admin' || role === 'captain' ? user.id : null
}

/// 관리자가 "응답 독촉하기"를 누른 일정의 후보 알림. 미응답 필터링은
/// buildDispatchTasks가 이미 하고 있으므로 여기서는 일정만 검증한다.
async function reminderCandidates(admin: AdminContext, eventId: string): Promise<PushCandidate[]> {
  const nowIso = new Date().toISOString()
  const rows = await getRows(admin, 'events', {
    select: 'id,title,response_deadline,starts_at,target_team,visibility',
    id: `eq.${eventId}`,
    response_enabled: 'eq.true',
    cancelled_at: 'is.null',
    starts_at: `gt.${nowIso}`,
    limit: '1',
  })
  const event = rows.length > 0 ? eventFromRow(rows[0]) : null
  if (!event) return []
  // 수동 발송은 몇 번을 눌러도 반복 보낼 수 있어야 하므로 dedupe 키에 시각을 넣는다.
  return [{
    category: 'events',
    id: event.id,
    title: '출결 응답 부탁드려요',
    body: clipped(`${event.title} · 아직 응답하지 않았어요. 참석 여부를 알려 주세요!`, 240),
    path: `/schedule/${encodeURIComponent(event.id)}`,
    dedupeKey: `attendance:${event.id}:manual-${Date.now()}`,
    event,
  }]
}

function announcementWebhookCandidates(record: JsonRecord): PushCandidate[] | null {
  if (record.is_urgent !== true) return []
  const id = stringValue(record.id)
  const title = stringValue(record.title).trim()
  const body = stringValue(record.body).trim()
  if (!id || !title || !body) return null
  return [announcementCandidate(id, title, body)]
}

async function cronCandidates(admin: AdminContext): Promise<PushCandidate[]> {
  const now = new Date()
  const recentSince = new Date(now.getTime() - recentAnnouncementWindowMs).toISOString()
  const reminderWindowEnd = new Date(now.getTime() + attendanceReminderLeadMs).toISOString()
  const nowIso = now.toISOString()

  const [announcementRows, eventRows] = await Promise.all([
    getRows(admin, 'announcements', {
      select: 'id,title,body,published_at',
      is_urgent: 'eq.true',
      published_at: `gte.${recentSince}`,
      order: 'published_at.desc',
      limit: '50',
    }),
    getRows(admin, 'events', {
      select: 'id,title,response_deadline,starts_at,target_team,visibility',
      response_enabled: 'eq.true',
      cancelled_at: 'is.null',
      response_deadline: `gt.${nowIso}`,
      starts_at: `gt.${nowIso}`,
      order: 'response_deadline.asc',
      limit: '50',
    }),
  ])

  const announcements = announcementRows.flatMap((row) => {
    const id = stringValue(row.id)
    const title = stringValue(row.title).trim()
    const body = stringValue(row.body).trim()
    return id && title && body ? [announcementCandidate(id, title, body)] : []
  })

  const events = eventRows.flatMap((row) => {
    const event = eventFromRow(row)
    if (!event) return []
    const deadline = Date.parse(event.responseDeadline)
    if (!Number.isFinite(deadline) || deadline > Date.parse(reminderWindowEnd)) return []
    return [eventCandidate(event)]
  })

  return [...announcements, ...events]
}

function announcementCandidate(id: string, title: string, body: string): PushCandidate {
  return {
    category: 'announcements',
    id,
    title: clipped(title, 120),
    body: clipped(body, 240),
    path: `/announcements/${encodeURIComponent(id)}`,
    dedupeKey: `announcement:${id}`,
  }
}

function eventCandidate(event: EventRow): PushCandidate {
  return {
    category: 'events',
    id: event.id,
    title: '출결 마감 3시간 전',
    body: clipped(`${event.title} 출결 응답 마감이 3시간 이내입니다.`, 240),
    path: `/schedule/${encodeURIComponent(event.id)}`,
    dedupeKey: `attendance:${event.id}:deadline-3h`,
    event,
  }
}

function eventFromRow(row: JsonRecord): EventRow | null {
  const id = stringValue(row.id)
  const title = stringValue(row.title).trim()
  const responseDeadline = stringValue(row.response_deadline)
  const startsAt = stringValue(row.starts_at)
  const targetTeam = stringValue(row.target_team)
  const visibility = stringValue(row.visibility)
  if (!id || !title || !responseDeadline || !startsAt || !targetTeam || !visibility) return null
  return { id, title, responseDeadline, startsAt, targetTeam, visibility }
}

async function loadSubscriptions(admin: AdminContext): Promise<PushSubscription[]> {
  const rows = await getRows(admin, 'push_subscriptions', {
    select: 'id,profile_id,fcm_token,categories',
    enabled: 'eq.true',
    order: 'id.asc',
  })
  return rows.flatMap((row) => {
    const id = integerValue(row.id)
    const profileId = stringValue(row.profile_id)
    const token = stringValue(row.fcm_token)
    const categories = Array.isArray(row.categories)
      ? row.categories.filter((value): value is string => typeof value === 'string')
      : []
    return id !== null && profileId && token
      ? [{ id, profileId, token, categories }]
      : []
  })
}

async function buildDispatchTasks(
  admin: AdminContext,
  candidates: PushCandidate[],
  subscriptions: PushSubscription[],
): Promise<DispatchTask[]> {
  const profileIds = unique(subscriptions.map((subscription) => subscription.profileId))
  const profileRows = await getRows(admin, 'profiles', {
    select: 'id,is_admin',
    id: inFilter(profileIds),
    is_active: 'eq.true',
  })
  const activeProfiles = new Map<string, ProfileAccess>()
  for (const row of profileRows) {
    const id = stringValue(row.id)
    if (id) activeProfiles.set(id, { isAdmin: row.is_admin === true, teams: new Set() })
  }
  if (activeProfiles.size === 0) return []

  const activeProfileIds = [...activeProfiles.keys()]
  const membershipRows = await getRows(admin, 'profile_teams', {
    select: 'profile_id,teams(code)',
    profile_id: inFilter(activeProfileIds),
  })
  for (const row of membershipRows) {
    const access = activeProfiles.get(stringValue(row.profile_id))
    if (!access) continue
    const team = isRecord(row.teams)
      ? stringValue(row.teams.code)
      : Array.isArray(row.teams) && isRecord(row.teams[0])
        ? stringValue(row.teams[0].code)
        : ''
    if (team) access.teams.add(team)
  }

  const events = candidates.flatMap((candidate) => candidate.event ? [candidate.event] : [])
  const eventIds = unique(events.map((event) => event.id))
  const confirmedRoster = new Set<string>()
  const attendance = new Map<string, string | null>()
  if (eventIds.length > 0) {
    const [rosterRows, attendanceRows] = await Promise.all([
      getRows(admin, 'event_roster', {
        select: 'event_id,profile_id',
        event_id: inFilter(eventIds),
        status: 'eq.confirmed',
      }),
      getRows(admin, 'event_attendance', {
        select: 'event_id,profile_id,choice',
        event_id: inFilter(eventIds),
      }),
    ])
    for (const row of rosterRows) {
      const eventId = stringValue(row.event_id)
      const profileId = stringValue(row.profile_id)
      if (eventId && profileId) confirmedRoster.add(pairKey(eventId, profileId))
    }
    for (const row of attendanceRows) {
      const eventId = stringValue(row.event_id)
      const profileId = stringValue(row.profile_id)
      if (eventId && profileId) {
        attendance.set(
          pairKey(eventId, profileId),
          typeof row.choice === 'string' ? row.choice : null,
        )
      }
    }
  }

  const tasks: DispatchTask[] = []
  for (const candidate of candidates) {
    for (const subscription of subscriptions) {
      if (!subscription.categories.includes(candidate.category)) continue
      const access = activeProfiles.get(subscription.profileId)
      if (!access) continue
      if (candidate.event) {
        if (!canAccessEvent(candidate.event, subscription.profileId, access, confirmedRoster)) {
          continue
        }
        const choice = attendance.get(pairKey(candidate.event.id, subscription.profileId))
        if (choice !== undefined && choice !== null && choice !== '미정') continue
      }
      tasks.push({ candidate, subscription })
    }
  }
  return tasks
}

function canAccessEvent(
  event: EventRow,
  profileId: string,
  access: ProfileAccess,
  confirmedRoster: Set<string>,
) {
  const targetTeam = event.targetTeam === '신입생' ? 'ENCBA' : event.targetTeam
  const canViewTeam = targetTeam === '전체' || access.isAdmin || access.teams.has(targetTeam)
  if (!canViewTeam) return false
  if (event.visibility === 'team') return true
  return event.visibility === 'confirmed_roster' &&
    (access.isAdmin || confirmedRoster.has(pairKey(event.id, profileId)))
}

async function firebaseAccessToken(serviceAccount: JsonRecord) {
  const auth = new GoogleAuth({
    credentials: serviceAccount,
    scopes: [firebaseMessagingScope],
  })
  const client = await auth.getClient()
  const tokenResult = await client.getAccessToken()
  return typeof tokenResult === 'string' ? tokenResult : tokenResult?.token ?? null
}

async function dispatchOne(
  admin: AdminContext,
  fcmProjectId: string,
  accessToken: string,
  task: DispatchTask,
): Promise<'sent' | 'skipped' | 'failed'> {
  let claimed = false
  try {
    claimed = await claimDelivery(
      admin,
      task.subscription.id,
      task.candidate.dedupeKey,
    )
    if (!claimed) return 'skipped'

    const result = await sendFcm(fcmProjectId, accessToken, task)
    if (result.ok) return 'sent'

    await releaseClaim(admin, task.subscription.id, task.candidate.dedupeKey)
    claimed = false
    if (result.unregistered) {
      await disableSubscription(admin, task.subscription.id)
    }
    return 'failed'
  } catch {
    if (claimed) {
      await releaseClaim(admin, task.subscription.id, task.candidate.dedupeKey).catch(() => {})
    }
    return 'failed'
  }
}

async function claimDelivery(
  admin: AdminContext,
  subscriptionId: number,
  dedupeKey: string,
) {
  const response = await fetch(restUrl(admin, 'push_deliveries'), {
    method: 'POST',
    headers: { ...admin.headers, Prefer: 'return=minimal' },
    body: JSON.stringify({ subscription_id: subscriptionId, dedupe_key: dedupeKey }),
  })
  if (response.ok) return true
  const errorBody = await response.json().catch(() => null)
  if (isRecord(errorBody) && errorBody.code === '23505') return false
  throw new Error('delivery claim failed')
}

async function releaseClaim(
  admin: AdminContext,
  subscriptionId: number,
  dedupeKey: string,
) {
  const response = await fetch(restUrl(admin, 'push_deliveries', {
    subscription_id: `eq.${subscriptionId}`,
    dedupe_key: `eq.${dedupeKey}`,
  }), {
    method: 'DELETE',
    headers: admin.headers,
  })
  if (!response.ok) throw new Error('delivery claim release failed')
}

async function disableSubscription(admin: AdminContext, subscriptionId: number) {
  const response = await fetch(restUrl(admin, 'push_subscriptions', {
    id: `eq.${subscriptionId}`,
  }), {
    method: 'PATCH',
    headers: { ...admin.headers, Prefer: 'return=minimal' },
    body: JSON.stringify({ enabled: false }),
  })
  if (!response.ok) throw new Error('subscription disable failed')
}

async function sendFcm(
  fcmProjectId: string,
  accessToken: string,
  task: DispatchTask,
): Promise<FcmResult> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(fcmProjectId)}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: task.subscription.token,
          notification: {
            title: task.candidate.title,
            body: task.candidate.body,
          },
          data: {
            path: task.candidate.path,
            category: task.candidate.category,
            id: task.candidate.id,
          },
        },
      }),
    },
  )
  if (response.ok) return { ok: true, unregistered: false }
  const errorBody = await response.json().catch(() => null)
  return {
    ok: false,
    unregistered: firebaseErrorCode(errorBody) === 'UNREGISTERED',
  }
}

function firebaseErrorCode(body: unknown) {
  if (!isRecord(body) || !isRecord(body.error) || !Array.isArray(body.error.details)) return ''
  for (const detail of body.error.details) {
    if (isRecord(detail) && typeof detail.errorCode === 'string') return detail.errorCode
  }
  return ''
}

async function getRows(
  admin: AdminContext,
  table: string,
  params: Record<string, string>,
): Promise<JsonRecord[]> {
  const response = await fetch(restUrl(admin, table, params), { headers: admin.headers })
  if (!response.ok) throw new Error('database read failed')
  const value = await response.json()
  if (!Array.isArray(value)) throw new Error('database response invalid')
  return value.filter(isRecord)
}

/// AdminContext를 아직 만들기 전(인증 확인 단계)에 쓰는 읽기 헬퍼.
async function getRowsWith(
  supabaseUrl: string,
  serviceRoleKey: string,
  table: string,
  params: Record<string, string>,
): Promise<JsonRecord[]> {
  const admin: AdminContext = {
    supabaseUrl: supabaseUrl.replace(/\/$/u, ''),
    headers: {
      Authorization: `Bearer ${serviceRoleKey}`,
      apikey: serviceRoleKey,
      'Content-Type': 'application/json',
    },
  }
  return getRows(admin, table, params)
}

function restUrl(
  admin: AdminContext,
  table: string,
  params: Record<string, string> = {},
) {
  const url = new URL(`${admin.supabaseUrl}/rest/v1/${table}`)
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value)
  return url.toString()
}

function inFilter(values: string[]) {
  return `in.(${values.join(',')})`
}

function pairKey(left: string, right: string) {
  return `${left}:${right}`
}

function clipped(value: string, maxLength: number) {
  const normalized = value.replace(/\s+/gu, ' ').trim()
  return normalized.length <= maxLength
    ? normalized
    : `${normalized.slice(0, maxLength - 1)}…`
}

function unique(values: string[]) {
  return [...new Set(values)]
}

function parseServiceAccount(value: string): JsonRecord | null {
  try {
    const parsed = JSON.parse(value)
    if (!isRecord(parsed)) return null
    return stringValue(parsed.client_email) && stringValue(parsed.private_key) ? parsed : null
  } catch {
    return null
  }
}

function integerValue(value: unknown) {
  if (typeof value === 'number' && Number.isSafeInteger(value)) return value
  if (typeof value === 'string' && /^\d+$/u.test(value)) {
    const parsed = Number(value)
    return Number.isSafeInteger(parsed) ? parsed : null
  }
  return null
}

function stringValue(value: unknown) {
  return typeof value === 'string' ? value : ''
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

async function mapConcurrent<T, R>(
  values: T[],
  concurrency: number,
  worker: (value: T) => Promise<R>,
) {
  const results = new Array<R>(values.length)
  let nextIndex = 0
  const runners = Array.from(
    { length: Math.min(concurrency, values.length) },
    async () => {
      while (true) {
        const index = nextIndex++
        if (index >= values.length) return
        results[index] = await worker(values[index])
      }
    },
  )
  await Promise.all(runners)
  return results
}

function json(body: JsonRecord, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json; charset=utf-8' },
  })
}

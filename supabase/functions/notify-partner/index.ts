import { createClient } from 'jsr:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

function corsHeadersForOrigin(origin: string | null) {
  // If you want to restrict this, set `ALLOWED_ORIGINS` to a comma-separated list.
  const allowed = (Deno.env.get('ALLOWED_ORIGINS') ?? '')
    .split(',')
    .map((v) => v.trim())
    .filter(Boolean)

  const allowOrigin =
    allowed.length === 0 ? (origin ?? '*') : allowed.includes(origin ?? '') ? (origin as string) : allowed[0]

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
}

type PushRow = {
  endpoint: string
  subscription: Record<string, unknown>
}

Deno.serve(async (request) => {
  const origin = request.headers.get('Origin')
  const corsHeaders = corsHeadersForOrigin(origin)

  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization) {
      return new Response(JSON.stringify({ error: 'Missing authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY') ?? ''
    const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY') ?? ''
    const vapidSubject = Deno.env.get('VAPID_SUBJECT') ?? 'mailto:hello@example.com'

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      throw new Error('Supabase environment variables are not fully configured')
    }

    if (!vapidPublicKey || !vapidPrivateKey) {
      return new Response(JSON.stringify({ skipped: true, reason: 'Missing VAPID configuration' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: {
          Authorization: authorization,
        },
      },
    })

    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser()

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = await request.json().catch(() => ({}))
    const preview =
      typeof body.preview === 'string' && body.preview.trim().length > 0
        ? body.preview.trim()
        : 'New message'

    const [{ data: senderProfile }, { data: pairRow }] = await Promise.all([
      adminClient.from('profiles').select('name').eq('id', user.id).maybeSingle(),
      adminClient.from('app_pair').select('user_a, user_b').maybeSingle(),
    ])

    const partnerId =
      pairRow && pairRow.user_a && pairRow.user_b
        ? pairRow.user_a === user.id
          ? pairRow.user_b
          : pairRow.user_b === user.id
            ? pairRow.user_a
            : null
        : null

    if (!partnerId) {
      return new Response(JSON.stringify({ sent: 0, removed: 0, skipped: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: subscriptions, error: subscriptionError } = await adminClient
      .from('push_subscriptions')
      .select('endpoint, subscription')
      .eq('user_id', partnerId)

    if (subscriptionError) {
      throw subscriptionError
    }

    if (!subscriptions || subscriptions.length === 0) {
      return new Response(JSON.stringify({ sent: 0, removed: 0, skipped: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey)

    const expiredEndpoints: string[] = []
    const notificationPayload = JSON.stringify({
      title: senderProfile?.name ?? 'HillsMeetSea',
      body: preview.length > 120 ? `${preview.slice(0, 117)}...` : preview,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      url: '/',
    })

    await Promise.all(
      (subscriptions as PushRow[]).map(async ({ endpoint, subscription }) => {
        try {
          await webpush.sendNotification(subscription as webpush.PushSubscription, notificationPayload)
        } catch (error) {
          const statusCode =
            typeof error === 'object' && error !== null && 'statusCode' in error
              ? Number((error as { statusCode: number }).statusCode)
              : undefined

          if (statusCode === 404 || statusCode === 410) {
            expiredEndpoints.push(endpoint)
            return
          }

          console.error('Failed to send push notification', error)
        }
      }),
    )

    if (expiredEndpoints.length > 0) {
      await adminClient.from('push_subscriptions').delete().in('endpoint', expiredEndpoints)
    }

    return new Response(
      JSON.stringify({
        sent: subscriptions.length - expiredEndpoints.length,
        removed: expiredEndpoints.length,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  } catch (error) {
    console.error(error)
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : 'Unknown error',
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }
})

import * as path from "path"
import { exec } from "child_process"
import { promisify } from "util"

const execAsync = promisify(exec)

const PUSHOVER_API_URL = "https://api.pushover.net/1/messages.json"
const DEBOUNCE_MS = 10000

// Pending debounce timers keyed by sessionID
const pending = new Map()

// Cached web URL promise — resolved once at startup
let webUrlPromise = null

/**
 * Resolve the opencode web UI URL using Tailscale MagicDNS, swapping in the
 * Tailscale hostname while preserving the port from the live serverUrl.
 *
 * serverUrl is provided by the opencode plugin SDK and contains the actual
 * port that this instance bound to (random when no port is pinned in config).
 *
 * Fallback chain: tailscale Self.DNSName → TAILSCALE_HOSTNAME env var → serverUrl as-is
 */
function resolveWebUrl(serverUrl) {
  if (webUrlPromise) return webUrlPromise

  let port = "4096"
  try {
    port = new URL(serverUrl).port || "4096"
  } catch {}

  webUrlPromise = execAsync("tailscale status --json")
    .then(({ stdout }) => {
      const status = JSON.parse(stdout)
      const dnsName = status?.Self?.DNSName?.replace(/\.$/, "") // strip trailing dot
      if (dnsName) {
        return `http://${dnsName}:${port}`
      }
      throw new Error("No DNSName in tailscale status")
    })
    .catch(() => {
      const envHost = process.env.TAILSCALE_HOSTNAME
      if (envHost) return `http://${envHost}:${port}`
      return serverUrl ?? `http://localhost:${port}`
    })

  return webUrlPromise
}

function clearPending(sessionID) {
  const timer = pending.get(sessionID)
  if (timer) {
    clearTimeout(timer)
    pending.delete(sessionID)
  }
}

async function sendPushoverNotification(title, message, url) {
  const token = process.env.PUSHOVER_APP_TOKEN
  const user = process.env.PUSHOVER_USER_KEY

  if (!token || !user) {
    console.error("[opencode-notify] Missing PUSHOVER_APP_TOKEN or PUSHOVER_USER_KEY")
    return
  }

  const params = { token, user, title, message }
  if (url) {
    params.url = url
    params.url_title = "Open in browser"
  }

  try {
    const response = await fetch(PUSHOVER_API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(params).toString(),
    })
    if (!response.ok) {
      console.error(`[opencode-notify] Pushover API error: ${response.status}`)
    }
  } catch (err) {
    console.error(`[opencode-notify] Failed to send notification: ${err}`)
  }
}

/**
 * Dispatch a notification with per-session debouncing.
 * Rapid back-to-back events (e.g. permission.updated + permission.ask)
 * collapse into a single notification.
 */
function dispatch(sessionID, title, message, url) {
  clearPending(sessionID)
  const timer = setTimeout(async () => {
    pending.delete(sessionID)
    await sendPushoverNotification(title, message, url)
  }, DEBOUNCE_MS)
  pending.set(sessionID, timer)
}

/**
 * Flush all pending debounced notifications immediately (used on process exit).
 */
async function flush() {
  const promises = []
  for (const [sessionID, timer] of pending.entries()) {
    clearTimeout(timer)
    pending.delete(sessionID)
    promises.push(timer._onFire?.())
  }
  await Promise.allSettled(promises)
}

/**
 * Enrich a notification with session context: project name, elapsed time,
 * last assistant text, subagent detection, and web URL.
 */
async function buildNotification(client, directory, sessionID, eventType, fallbackMessage) {
  const projectName = directory ? path.basename(directory) : "opencode"

  let elapsedSeconds = null
  let isSubagent = false
  let assistantText = null

  try {
    if (sessionID && client) {
      const sessionResult = await client.session.get({ path: { id: sessionID } })
      if (sessionResult.data?.parentID) {
        isSubagent = true
      }

      const messagesResult = await client.session.messages({ path: { id: sessionID } })
      const messages = messagesResult.data
      if (messages && messages.length > 0) {
        const firstUser = messages.find((m) => m.info?.role === "user")
        if (firstUser?.info?.time?.created) {
          elapsedSeconds = Math.floor((Date.now() - new Date(firstUser.info.time.created).getTime()) / 1000)
        }

        const lastAssistant = [...messages].reverse().find((m) => m.info?.role === "assistant")
        if (lastAssistant?.parts) {
          const textParts = lastAssistant.parts.filter((p) => p.type === "text")
          const last = textParts[textParts.length - 1]
          if (last?.text?.trim()) {
            assistantText = last.text.trim()
          }
        }
      }
    }
  } catch {
    // SDK calls may fail — fall back to nulls
  }

  const resolvedType = eventType === "complete" && isSubagent ? "subagent_complete" : eventType

  const emojis = {
    complete: "\u2705",
    subagent_complete: "\u2705",
    error: "\u274c",
    permission: "\u26a0\ufe0f",
    question: "\u2753",
  }
  const emoji = emojis[resolvedType] ?? ""

  const title = `${emoji} [${resolvedType}] ${projectName}`

  let message = fallbackMessage ?? assistantText ?? "Session event"
  if (elapsedSeconds !== null) {
    const m = Math.floor(elapsedSeconds / 60)
    const s = elapsedSeconds % 60
    message += ` (${m}m ${s}s)`
  }

  const url = await resolveWebUrl(null)

  return { title, message, resolvedType, url }
}

export const PushoverNotifyPlugin = async (input) => {
  if (process.env.OPENCODE_NOTIFY === "0") {
    console.log("[opencode-notify] Notifications disabled (OPENCODE_NOTIFY=0)")
    return {}
  }

  const token = process.env.PUSHOVER_APP_TOKEN
  const user = process.env.PUSHOVER_USER_KEY
  if (!token || !user) {
    console.warn("[opencode-notify] Missing credentials. Set PUSHOVER_APP_TOKEN and PUSHOVER_USER_KEY")
  } else {
    console.log("[opencode-notify] Plugin loaded")
  }

  const { client, directory, serverUrl } = input

  // Kick off Tailscale hostname resolution eagerly so it's ready by first notification
  resolveWebUrl(serverUrl)

  // Flush any debounced notifications when the process is about to exit
  let flushed = false
  process.on("beforeExit", async () => {
    if (flushed) return
    flushed = true
    await flush()
  })

  async function eventHook({ event }) {
    try {
      const sessionID = event.properties?.sessionID ?? null

      if (event.type === "session.idle") {
        const { title, message, resolvedType, url } = await buildNotification(client, directory, sessionID, "complete")
        if (resolvedType === "subagent_complete") return // skip subagent completions
        dispatch(sessionID, title, message, url)
      } else if (event.type === "session.error") {
        const rawError = event.properties?.error
        const errorMessage = rawError?.data?.message ?? rawError?.name ?? "Unknown error"
        const { title, message, url } = await buildNotification(client, directory, sessionID, "error", errorMessage)
        dispatch(sessionID, title, message, url)
      } else if (event.type === "permission.updated") {
        const { title, message, url } = await buildNotification(client, directory, sessionID, "permission")
        dispatch(sessionID, title, message, url)
      }
    } catch (err) {
      console.error(`[opencode-notify] Event hook error: ${err}`)
    }
  }

  async function permissionAskHook(hookInput) {
    try {
      const sessionID = hookInput?.sessionID ?? null
      const { title, message, url } = await buildNotification(client, directory, sessionID, "permission")
      dispatch(sessionID, title, message, url)
    } catch (err) {
      console.error(`[opencode-notify] Permission.ask hook error: ${err}`)
    }
  }

  async function toolExecuteBeforeHook(hookInput) {
    try {
      if (hookInput?.tool === "question") {
        const sessionID = hookInput?.sessionID ?? null
        const { title, message, url } = await buildNotification(client, directory, sessionID, "question")
        dispatch(sessionID, title, message, url)
      }
    } catch (err) {
      console.error(`[opencode-notify] Tool.execute.before hook error: ${err}`)
    }
  }

  return {
    event: eventHook,
    "permission.ask": permissionAskHook,
    "tool.execute.before": toolExecuteBeforeHook,
  }
}

export default PushoverNotifyPlugin

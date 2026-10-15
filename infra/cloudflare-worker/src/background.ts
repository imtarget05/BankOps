/**
 * Queue consumer for background operational events.
 *
 * This Worker intentionally does not contain inventory business logic.  The
 * canonical FastAPI service owns stock mutations; this consumer only accepts
 * allow-listed, non-sensitive operational event envelopes and records their
 * processing for Cloudflare Logs/Traces.  Unknown payloads are retried and
 * ultimately routed to the dead-letter queue instead of being discarded.
 */

type OperationalEventType =
  | "inventory.sync.requested"
  | "stock.alert.requested"
  | "report.export.requested";

interface OperationalEvent {
  event_type: OperationalEventType;
  event_id: string;
  occurred_at: string;
  correlation_id?: string;
}

function isOperationalEvent(value: unknown): value is OperationalEvent {
  if (!value || typeof value !== "object") return false;
  const event = value as Record<string, unknown>;
  return (
    typeof event.event_id === "string" &&
    typeof event.occurred_at === "string" &&
    (event.event_type === "inventory.sync.requested" ||
      event.event_type === "stock.alert.requested" ||
      event.event_type === "report.export.requested") &&
    (event.correlation_id === undefined ||
      typeof event.correlation_id === "string")
  );
}

export default {
  // Kept explicit so the Worker cannot accidentally become a public API.
  fetch(): Response {
    return new Response("Not found", { status: 404 });
  },

  async queue(
    batch: MessageBatch<unknown>,
    _env: Record<string, never>,
    _ctx: ExecutionContext
  ): Promise<void> {
    for (const message of batch.messages) {
      if (!isOperationalEvent(message.body)) {
        // Do not acknowledge unknown data. Cloudflare applies the configured
        // retry policy and sends exhausted messages to the DLQ for review.
        message.retry();
        continue;
      }

      // Deliberately log only operational metadata: no user, token, or stock
      // row payload is emitted to observability systems.
      console.log(
        JSON.stringify({
          event: "queue.processed",
          event_type: message.body.event_type,
          event_id: message.body.event_id,
          occurred_at: message.body.occurred_at,
          correlation_id: message.body.correlation_id,
        })
      );
      message.ack();
    }
  },
} satisfies ExportedHandler<Record<string, never>, unknown>;

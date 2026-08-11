"""Structured logging that carries the active trace identity.

Every log record is emitted as a single JSON object on stdout. When the record
is produced inside an active span, the record also carries `trace_id` and
`span_id`. `trace_id` is rendered in AWS X-Ray's own format so the value can be
pasted straight into the X-Ray console, and CloudWatch Logs Insights can filter
on it as a first-class field.

That shared identifier is the whole point: it is what lets a trace in X-Ray and
the log lines for that same request find each other.
"""

import json
import logging
import sys
from datetime import UTC, datetime

from opentelemetry import trace

# Uvicorn installs its own handlers and would otherwise emit plain text
# alongside our JSON, producing a log stream in two different shapes.
_UVICORN_LOGGERS = ("uvicorn", "uvicorn.error", "uvicorn.access")


def format_trace_id(trace_id: int) -> str:
    """Render a 128-bit OpenTelemetry trace id in AWS X-Ray's string form.

    X-Ray writes a trace id as ``1-<8 hex: epoch seconds>-<24 hex: random>``
    rather than as a flat 32-character hex string. The bytes are identical; only
    the presentation differs. Emitting the X-Ray form means the id in a log line
    is the same string the X-Ray console shows, with no conversion step for
    whoever is debugging at 3am.
    """
    hex_id = format(trace_id, "032x")
    return f"1-{hex_id[:8]}-{hex_id[8:]}"


class JsonFormatter(logging.Formatter):
    """Render log records as one-line JSON, annotated with trace context."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        span_context = trace.get_current_span().get_span_context()
        if span_context.is_valid:
            payload["trace_id"] = format_trace_id(span_context.trace_id)
            payload["span_id"] = format(span_context.span_id, "016x")

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        # Anything passed through `logger.info(..., extra={...})` rides along.
        for key, value in getattr(record, "__dict__", {}).items():
            if key.startswith("otel_") or key in ("hero_id", "event"):
                payload[key] = value

        return json.dumps(payload, default=str)


def configure_logging(level: str = "INFO") -> None:
    """Point the root logger — and uvicorn's — at a single JSON handler."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)

    for name in _UVICORN_LOGGERS:
        uvicorn_logger = logging.getLogger(name)
        uvicorn_logger.handlers = []
        uvicorn_logger.propagate = True

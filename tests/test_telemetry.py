"""Traces and logs must share an identifier, and it must be X-Ray shaped.

This is the correlation requirement expressed as executable assertions: if
someone later swaps the id generator or drops the trace fields from the log
formatter, these fail rather than the link silently disappearing in production.
"""

import json
import logging

from fastapi.testclient import TestClient
from opentelemetry import trace
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

from src.core.logging import JsonFormatter, format_trace_id


def test_trace_id_is_rendered_in_xray_format() -> None:
    rendered = format_trace_id(0x67AB3F219C8D7E6F5A4B3C2D1E0F1122)

    # 1-<8 hex epoch>-<24 hex random>, exactly as the X-Ray console displays it.
    assert rendered == "1-67ab3f21-9c8d7e6f5a4b3c2d1e0f1122"


def test_generated_trace_ids_are_xray_compatible(
    client: TestClient, spans: InMemorySpanExporter
) -> None:
    """X-Ray rejects ids whose first 32 bits are not a plausible timestamp."""
    client.get("/heroes/")

    recorded = spans.get_finished_spans()
    assert recorded, "instrumentation produced no spans"

    rendered = format_trace_id(recorded[-1].context.trace_id)
    prefix, epoch, random_part = rendered.split("-")

    assert prefix == "1"
    assert len(epoch) == 8 and int(epoch, 16) > 0
    assert len(random_part) == 24


def test_log_records_inside_a_span_carry_the_trace_id() -> None:
    formatter = JsonFormatter()
    tracer = trace.get_tracer(__name__)

    with tracer.start_as_current_span("unit") as span:
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname=__file__,
            lineno=1,
            msg="something happened",
            args=(),
            exc_info=None,
        )
        payload = json.loads(formatter.format(record))
        expected = format_trace_id(span.get_span_context().trace_id)

    assert payload["trace_id"] == expected
    assert len(payload["span_id"]) == 16
    assert payload["message"] == "something happened"


def test_log_records_outside_a_span_omit_trace_fields() -> None:
    """No invalid or zeroed ids in the log stream — absent is clearer."""
    record = logging.LogRecord(
        name="test",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="no span here",
        args=(),
        exc_info=None,
    )

    payload = json.loads(JsonFormatter().format(record))

    assert "trace_id" not in payload
    assert "span_id" not in payload


def test_health_checks_are_not_traced(
    client: TestClient, spans: InMemorySpanExporter
) -> None:
    """Probe traffic would otherwise dominate X-Ray volume and cost."""
    client.get("/health")

    assert spans.get_finished_spans() == ()


def test_readiness_probe_emits_no_orphan_database_spans(
    client: TestClient, spans: InMemorySpanExporter
) -> None:
    """Excluding the route is not enough on its own.

    `excluded_urls` suppresses the HTTP server span, but the SQLAlchemy span
    nested inside it survives — and with no parent it becomes a root trace.
    Probing would then produce a stream of one-span traces in X-Ray. This
    asserts the suppression that prevents it.
    """
    client.get("/ready")

    assert spans.get_finished_spans() == ()

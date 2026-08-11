import os

# Set before importing the application: config.py fails fast without it, and no
# connection is ever opened because SQLAlchemy engines are lazy.
os.environ.setdefault(
    "DATABASE_URL", "postgresql+psycopg://test:test@127.0.0.1:5599/test"
)
os.environ.setdefault("OTEL_SDK_DISABLED", "false")

import pytest
from fastapi.testclient import TestClient
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

from src.main import app


@pytest.fixture(scope="session")
def client() -> TestClient:
    """Client that surfaces handler exceptions as 500s instead of re-raising."""
    return TestClient(app, raise_server_exceptions=False)


@pytest.fixture(scope="session")
def _span_exporter() -> InMemorySpanExporter:
    exporter = InMemorySpanExporter()

    # The global provider is the SDK implementation only when setup_telemetry
    # installed one. Asserting it makes the failure mode obvious if telemetry is
    # ever disabled by default, instead of silently collecting zero spans.
    provider = trace.get_tracer_provider()
    assert isinstance(provider, TracerProvider), (
        "telemetry is not installed; these tests would assert nothing"
    )

    provider.add_span_processor(SimpleSpanProcessor(exporter))
    return exporter


@pytest.fixture
def spans(_span_exporter: InMemorySpanExporter) -> InMemorySpanExporter:
    _span_exporter.clear()
    return _span_exporter

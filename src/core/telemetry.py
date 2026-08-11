"""OpenTelemetry tracing, wired for AWS X-Ray.

The application speaks vendor-neutral OTLP and knows nothing about X-Ray beyond
two details it cannot avoid:

* **Trace id shape.** X-Ray rejects ids whose leading 32 bits are not a recent
  epoch timestamp, so `AwsXRayIdGenerator` must produce them.
* **Propagation header.** AWS load balancers and SDKs pass trace context in the
  `X-Amzn-Trace-Id` header, not W3C `traceparent`, so `AwsXRayPropagator` must
  read and write it. Without this, a request arriving through the ALB starts a
  brand-new trace instead of continuing the existing one.

Everything else — where spans end up, how they are batched — is the collector's
problem, configured in `observability/`.
"""

import logging
import os

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.aws import AwsXRayPropagator
from opentelemetry.sdk.extension.aws.trace import AwsXRayIdGenerator
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

logger = logging.getLogger(__name__)

# Health probes fire every few seconds from every load balancer node. Tracing
# them would bury real traffic in noise and bill X-Ray for the privilege.
EXCLUDED_URLS = "health,ready"


def _is_disabled() -> bool:
    return os.getenv("OTEL_SDK_DISABLED", "false").lower() in ("1", "true", "yes")


def setup_telemetry(app: FastAPI) -> None:
    """Install tracing on the app. Safe to call when no collector is present."""
    if _is_disabled():
        logger.info("telemetry disabled via OTEL_SDK_DISABLED")
        return

    # Resource attributes are what let X-Ray group spans into named services.
    # OTEL_RESOURCE_ATTRIBUTES and OTEL_SERVICE_NAME are picked up automatically.
    resource = Resource.create(
        {
            "service.name": os.getenv("OTEL_SERVICE_NAME", "devops-assessment-api"),
            "deployment.environment": os.getenv("ENVIRONMENT", "local"),
        }
    )

    provider = TracerProvider(resource=resource, id_generator=AwsXRayIdGenerator())

    # Export only when a collector address is actually configured. Instrumentation
    # stays on either way, so trace ids still reach the logs; what is skipped is a
    # background thread retrying against an endpoint nobody is listening on. That
    # matters for test runs and for anyone starting the app bare.
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if endpoint:
        # Batching matters here: one gRPC call per span would add network latency
        # to every request. BatchSpanProcessor exports on a background thread.
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))

    trace.set_tracer_provider(provider)
    set_global_textmap(AwsXRayPropagator())

    FastAPIInstrumentor.instrument_app(app, excluded_urls=EXCLUDED_URLS)

    # Imported here rather than at module scope so that importing this module
    # never constructs a database engine as a side effect.
    from src.core.db import engine

    # The async engine wraps a sync engine; the instrumentation hooks the latter.
    SQLAlchemyInstrumentor().instrument(engine=engine.sync_engine)

    logger.info(
        "telemetry enabled",
        extra={
            "otel_endpoint": endpoint or "(none: spans generated, not exported)",
            "otel_service_name": resource.attributes.get("service.name"),
        },
    )

import logging

from fastapi import FastAPI
from opentelemetry import metrics, trace
from opentelemetry._logs import set_logger_provider
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from api.routers.journal_router import router as journal_router


def setup_telemetry(service_name: str = "journal_api"):
    """
    Sets up telemetry for the application.

    Args:
        service_name (str): The name of the service for telemetry purposes.
    """
    resource = Resource.create({"service.name": service_name})
    # Traces
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(tracer_provider)

    # Metrics
    reader = PeriodicExportingMetricReader(OTLPMetricExporter(), export_interval_millis=10_000)
    meter_provider = MeterProvider(resource=resource, metric_readers=[reader])
    metrics.set_meter_provider(meter_provider)

    # Logs: bridge stdlib logging into OTel
    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter()))
    set_logger_provider(logger_provider)

    handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
    logging.getLogger().addHandler(handler)
    logging.getLogger().setLevel(logging.INFO)

    return tracer_provider, meter_provider, logger_provider


# TODO (Task 1): Configure logging here.
# Reference: https://docs.python.org/3/howto/logging.html
# Steps:
#   1. ``import logging`` at the top of this file.
#   2. Call ``logging.basicConfig(level=logging.INFO, format="...")``.
#   3. Log an INFO message on startup (e.g. "Journal API starting up").


logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

setup_telemetry(service_name="journal_api")
logging.info("Journal API starting up")

app = FastAPI(
    title="Journal API",
    description="A simple journal API for tracking daily work, struggles, and intentions",
)

FastAPIInstrumentor.instrument_app(app)
app.include_router(journal_router)

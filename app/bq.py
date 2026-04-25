import os
import uuid
from datetime import datetime, timezone

from google.cloud import bigquery

BQ_PROJECT_ID = os.environ.get("BQ_PROJECT_ID")
BQ_DATASET = os.environ.get("BQ_DATASET", "analytics")
BQ_TABLE = os.environ.get("BQ_TABLE", "todo_events")

_client = bigquery.Client(project=BQ_PROJECT_ID) if BQ_PROJECT_ID else None


def log_todo_event(todo_id: int, action: str, title: str | None = None) -> None:
    if _client is None:
        return

    table_id = f"{BQ_PROJECT_ID}.{BQ_DATASET}.{BQ_TABLE}"
    row = {
        "event_id": str(uuid.uuid4()),
        "todo_id": todo_id,
        "action": action,
        "title": title,
        "event_time": datetime.now(timezone.utc).isoformat(),
    }
    errors = _client.insert_rows_json(table_id, [row])
    if errors:
        print(f"BigQuery insert errors: {errors}")
"""
The ingest API against the shared contract (dpcommon.ingest).

DataPoints' tests build these same fixtures from its articles; here every one
of them must be accepted by the route, so the two sides can't drift apart.
"""

import pytest
from dpcommon.ingest import INGEST_BATCH_PATH, INGEST_ITEMS_PATH, IngestItemResponse, load_fixtures

FIXTURES = sorted(load_fixtures().items())


@pytest.mark.parametrize("name,payload", FIXTURES, ids=[n for n, _ in FIXTURES])
def test_route_accepts_every_contract_fixture(client, name, payload):
    resp = client.post(INGEST_ITEMS_PATH, json=payload)
    assert resp.status_code == 200, resp.text
    body = IngestItemResponse.model_validate(resp.json())
    assert body.already_existed is False
    assert body.url == f"composer://item/{body.id}"


def test_full_fixture_is_stored_field_for_field(client):
    payload = load_fixtures()["datapoints_full"]
    item_id = client.post(INGEST_ITEMS_PATH, json=payload).json()["id"]

    from backend.config import state

    item = state.items.get(item_id)
    assert item.source == "datapoints"
    assert item.source_ref == payload["source_ref"]
    assert item.title == payload["title"]
    assert item.summary == payload["summary"]
    assert item.key_points == payload["key_points"]
    assert item.keywords == payload["keywords"]
    assert item.related_links == payload["related_links"]
    assert item.metadata == payload["metadata"]
    assert client.indexed == [item_id]


def test_sender_from_before_the_contract(client):
    # Production DataPoints doesn't send schema_version yet
    payload = load_fixtures()["datapoints_minimal"]
    assert "schema_version" not in payload
    assert client.post(INGEST_ITEMS_PATH, json=payload).status_code == 200


def test_ingest_is_idempotent_on_source_ref(client):
    payload = load_fixtures()["datapoints_full"]
    first = client.post(INGEST_ITEMS_PATH, json=payload).json()
    again = client.post(INGEST_ITEMS_PATH, json={**payload, "title": "Retitled"}).json()
    assert again["id"] == first["id"]
    assert again["already_existed"] is True


def test_unknown_fields_are_ignored(client):
    payload = {**load_fixtures()["manual_title_only"], "added_in_a_later_version": True}
    assert client.post(INGEST_ITEMS_PATH, json=payload).status_code == 200


def test_payload_outside_the_contract_is_rejected(client):
    assert client.post(INGEST_ITEMS_PATH, json={"source": "datapoints"}).status_code == 422
    future = {**load_fixtures()["manual_title_only"], "schema_version": 2}
    assert client.post(INGEST_ITEMS_PATH, json=future).status_code == 422


def test_batch_counts_created_and_skipped(client):
    fixtures = load_fixtures()
    batch = [fixtures["datapoints_full"], fixtures["datapoints_minimal"], fixtures["datapoints_full"]]
    body = client.post(INGEST_BATCH_PATH, json=batch).json()
    assert (body["created"], body["skipped"]) == (2, 1)
    assert body["items"][0]["id"] == body["items"][2]["id"]


def test_ingest_key_enforced_when_configured(client, monkeypatch):
    from backend.config import config

    monkeypatch.setattr(config, "INGEST_API_KEY", "secret")
    payload = load_fixtures()["manual_title_only"]
    assert client.post(INGEST_ITEMS_PATH, json=payload).status_code == 401
    ok = client.post(INGEST_ITEMS_PATH, json=payload, headers={"X-Ingest-Key": "secret"})
    assert ok.status_code == 200

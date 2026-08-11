"""The contract the load balancer depends on.

If these break, a deploy can go green while the target group never turns
healthy — so they are worth asserting explicitly.
"""

from fastapi.testclient import TestClient


def test_health_is_ok_without_any_dependency(client: TestClient) -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_reports_degraded_when_database_is_unreachable(
    client: TestClient,
) -> None:
    """`/ready` must degrade, not crash.

    A 503 with a readable body tells an operator what is wrong; an unhandled
    exception tells them only that something is.
    """
    response = client.get("/ready")

    assert response.status_code == 503
    assert response.json() == {"status": "degraded", "database": "unreachable"}


def test_liveness_is_independent_of_readiness(client: TestClient) -> None:
    """The whole point of splitting the two probes.

    With the database down, readiness fails and liveness still passes — which is
    what stops ECS from replacing tasks that are perfectly healthy.
    """
    assert client.get("/ready").status_code == 503
    assert client.get("/health").status_code == 200

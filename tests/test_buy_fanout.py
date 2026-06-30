from json import JSONDecodeError

from task.buy import (
    _CreateFanoutLane,
    _CreateFanoutResult,
    _create_fanout_lane,
    _find_successful_fanout_result,
    _run_create_fanout_round,
)
from util.request.exceptions import BiliRateLimitError


class FakeResponse:
    def __init__(self, status_code: int, payload: dict | None = None):
        self.status_code = status_code
        self._payload = payload

    def json(self):
        if self._payload is None:
            raise JSONDecodeError("not json", "", 0)
        return self._payload


class FakeRequest:
    def __init__(self, response=None, exc: Exception | None = None):
        self.response = response
        self.exc = exc
        self.calls = 0

    def post(self, **kwargs):
        self.calls += 1
        if self.exc is not None:
            raise self.exc
        return self.response


def test_fanout_round_reports_successful_lane():
    request = FakeRequest(FakeResponse(200, {"errno": 0, "data": {"orderId": 1}}))
    lane = _CreateFanoutLane("http://p1:1", request)

    results = _run_create_fanout_round(
        [lane],
        attempt=1,
        attempt_limit=3,
        url="https://show.bilibili.com/api/ticket/order/createV2",
        payload={"token": "t"},
    )

    assert len(results) == 1
    assert results[0].lane is lane
    assert results[0].attempt == 1
    assert results[0].err == 0
    assert results[0].ret == {"errno": 0, "data": {"orderId": 1}}
    assert request.calls == 1


def test_fanout_round_keeps_rate_limit_as_lane_result():
    exc = BiliRateLimitError("请求被限流(HTTP 429)")
    request = FakeRequest(exc=exc)
    lane = _CreateFanoutLane("http://p1:1", request)

    results = _run_create_fanout_round(
        [lane],
        attempt=2,
        attempt_limit=3,
        url="https://show.bilibili.com/api/ticket/order/createV2",
        payload={"token": "t"},
    )

    assert len(results) == 1
    assert results[0].lane is lane
    assert results[0].attempt == 2
    assert results[0].exc is exc


def test_fanout_round_marks_412_non_json_for_lane_discard():
    request = FakeRequest(FakeResponse(412))
    lane = _CreateFanoutLane("http://p1:1", request)

    results = _run_create_fanout_round(
        [lane],
        attempt=3,
        attempt_limit=3,
        url="https://show.bilibili.com/api/ticket/order/createV2",
        payload={"token": "t"},
    )

    assert len(results) == 1
    assert results[0].lane is lane
    assert results[0].attempt == 3
    assert results[0].response.status_code == 412
    assert isinstance(results[0].exc, JSONDecodeError)


def test_fanout_success_wins_over_earlier_token_expiry():
    token_lane = _CreateFanoutLane("http://p1:1", FakeRequest())
    success_lane = _CreateFanoutLane("http://p2:2", FakeRequest())
    token_expired = _CreateFanoutResult(
        lane=token_lane,
        attempt=1,
        ret={"errno": 100051},
        err=100051,
    )
    success = _CreateFanoutResult(
        lane=success_lane,
        attempt=2,
        ret={"errno": 0, "data": {"orderId": 1}},
        err=0,
    )

    assert _find_successful_fanout_result([token_expired, success]) is success


def test_fanout_success_detector_returns_none_without_success():
    lane = _CreateFanoutLane("http://p1:1", FakeRequest())
    terminal = _CreateFanoutResult(
        lane=lane,
        attempt=1,
        ret={"errno": 100079},
        err=100079,
    )

    assert _find_successful_fanout_result([terminal]) is None


def test_create_fanout_lane_reuses_main_browser_state():
    browser_state = {
        "navigator": {"userAgent": "Mozilla/5.0 TestBrowser/1.0"},
        "location": {"origin": "https://show.bilibili.com"},
        "storage": {},
    }

    lane = _create_fanout_lane(
        "http://p1:1",
        cookies=[],
        browser_state=browser_state,
        proxy_failure_threshold=2,
        proxy_cooldown_seconds=180,
    )

    assert lane.request.browser_state is browser_state
    assert lane.request.get_user_agent() == "Mozilla/5.0 TestBrowser/1.0"

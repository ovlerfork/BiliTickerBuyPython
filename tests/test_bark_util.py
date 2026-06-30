import json
from urllib.parse import unquote, urlparse

import pytest

from util.notifer.BarkUtil import BarkNotifier
from util.notifer import BarkUtil


class _Response:
    def __init__(self, payload=None):
        self.payload = payload or {"code": 200, "message": "success"}
        self.raise_called = False

    def raise_for_status(self):
        self.raise_called = True

    def json(self):
        return self.payload


def _decode_last_path_parts(url, count):
    parts = urlparse(url).path.strip("/").split("/")
    return [unquote(part) for part in parts[-count:]]


def test_bark_encodes_title_and_message_in_url(monkeypatch):
    calls = {}
    response = _Response()

    def fake_post(url, headers=None, data=None, timeout=None):
        calls.update(
            {"url": url, "headers": headers, "data": data, "timeout": timeout}
        )
        return response

    monkeypatch.setattr(BarkUtil.requests, "post", fake_post)

    notifier = BarkNotifier("device-key", "unused", "unused")
    notifier.send_message("抢票提醒", "内容 [#1] https://example.test/a/b")

    parsed = urlparse(calls["url"])
    assert parsed.fragment == ""
    assert parsed.netloc == "api.day.app"
    assert _decode_last_path_parts(calls["url"], 2) == [
        "抢票提醒",
        "内容 [#1] https://example.test/a/b",
    ]
    assert json.loads(calls["data"])["level"] == "critical"
    assert calls["timeout"] == 10
    assert response.raise_called is True


def test_bark_uses_self_hosted_push_path(monkeypatch):
    calls = {}

    def fake_post(url, **kwargs):
        calls["url"] = url
        return _Response()

    monkeypatch.setattr(BarkUtil.requests, "post", fake_post)

    notifier = BarkNotifier(" https://bark.example.test/custom-key/ ", "", "")
    notifier.send_message("title", "message")

    assert calls["url"] == "https://bark.example.test/custom-key/title/message"


def test_bark_raises_when_response_code_is_not_success(monkeypatch):
    def fake_post(url, **kwargs):
        return _Response({"code": 400, "message": "bad key"})

    monkeypatch.setattr(BarkUtil.requests, "post", fake_post)

    notifier = BarkNotifier("device-key", "", "")
    with pytest.raises(RuntimeError, match="Bark push failed"):
        notifier.send_message("title", "message")

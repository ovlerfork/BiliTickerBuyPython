import json
import requests

from urllib.parse import quote, urlparse
from util.notifer.Notifier import NotifierBase


class BarkNotifier(NotifierBase):
    def __init__(self, token, title, content, interval_seconds=10, duration_minutes=10):
        super().__init__(title, content, interval_seconds, duration_minutes)
        self.token = token

    def send_message(self, title, message):
        headers = {"Content-Type": "application/json"}
        data = {
            "icon": "https://raw.githubusercontent.com/mikumifa/biliTickerBuy/refs/heads/main/assets/icon.ico",  # 推送LOGO
            "group": "biliTickerBuy",
            "url": "https://mall.bilibili.com/neul/index.html?page=box_me&noTitleBar=1",  # 跳转会员购链接
            "sound": "telegraph",  # 警告铃声
            "level": "critical",  # 重要警告
            "volume": "10",
        }
        encoded_title = quote(str(title), safe="")
        encoded_message = quote(str(message), safe="")
        token_text = str(self.token or "").strip()

        if not token_text:
            raise ValueError("Bark token is required")

        if urlparse(token_text).scheme in {"http", "https"}:
            url = f"{token_text.rstrip('/')}/{encoded_title}/{encoded_message}"
        else:
            token = quote(token_text.strip("/"), safe="")
            url = f"https://api.day.app/{token}/{encoded_title}/{encoded_message}"

        response = requests.post(url, headers=headers, data=json.dumps(data), timeout=10)
        response.raise_for_status()

        try:
            result = response.json()
        except ValueError:
            return

        if result.get("code") != 200:
            raise RuntimeError(f"Bark push failed: {result}")

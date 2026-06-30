from typing import Any


QUEUE_PROXY_FANOUT_FILL_STRATEGY_DEFAULT = "pool_api"
QUEUE_PROXY_FANOUT_412_ACTION_DEFAULT = "replace"
QUEUE_PROXY_FANOUT_FILL_STRATEGIES = {
    "api",
    "pool",
    "pool_api",
    "pool_api_direct",
}
QUEUE_PROXY_FANOUT_412_ACTIONS = {"cooldown", "replace"}


def normalize_queue_proxy_fanout_fill_strategy(value: Any) -> str:
    normalized = str(value or QUEUE_PROXY_FANOUT_FILL_STRATEGY_DEFAULT)
    normalized = normalized.strip().lower().replace("-", "_")
    if normalized not in QUEUE_PROXY_FANOUT_FILL_STRATEGIES:
        raise ValueError("invalid queue proxy fan-out fill strategy")
    return normalized


def normalize_queue_proxy_fanout_412_action(value: Any) -> str:
    normalized = str(value or QUEUE_PROXY_FANOUT_412_ACTION_DEFAULT)
    normalized = normalized.strip().lower().replace("-", "_")
    if normalized not in QUEUE_PROXY_FANOUT_412_ACTIONS:
        raise ValueError("invalid queue proxy fan-out 412 action")
    return normalized


def queue_proxy_fanout_strategy_uses_pool(strategy: str) -> bool:
    return normalize_queue_proxy_fanout_fill_strategy(strategy) in {
        "pool",
        "pool_api",
        "pool_api_direct",
    }


def queue_proxy_fanout_strategy_uses_api(strategy: str) -> bool:
    return normalize_queue_proxy_fanout_fill_strategy(strategy) in {
        "api",
        "pool_api",
        "pool_api_direct",
    }


def queue_proxy_fanout_strategy_uses_direct(strategy: str) -> bool:
    return normalize_queue_proxy_fanout_fill_strategy(strategy) == "pool_api_direct"

from tab.go import (
    QueueProxyAllocator,
    _is_queue_fanout_enabled,
    _queue_fanout_start_error,
    _queue_worker_count,
    _real_proxy_list,
)


def test_real_proxy_list_excludes_direct_when_proxies_are_configured():
    assert _real_proxy_list("none,http://p1:1,direct,http://p2:2") == [
        "http://p1:1",
        "http://p2:2",
    ]


def test_allocator_uses_existing_pool_proxies_without_repeating():
    allocator = QueueProxyAllocator(
        proxies=[
            "http://p1:1",
            "http://p2:2",
            "http://p3:3",
            "http://p4:4",
        ],
        api_url="http://proxy-api.example",
        multiplier=2,
        fill_strategy="pool",
    )

    first, first_error = allocator.allocate()
    second, second_error = allocator.allocate()

    assert first_error is None
    assert second_error is None
    assert first == ["http://p1:1", "http://p2:2"]
    assert second == ["http://p3:3", "http://p4:4"]
    assert set(first).isdisjoint(second)


def test_allocator_api_strategy_does_not_consume_configured_pool():
    allocator = QueueProxyAllocator(
        proxies=["http://p1:1", "http://p2:2"],
        api_url="http://proxy-api.example",
        multiplier=2,
        fill_strategy="api",
    )

    assigned, error = allocator.allocate()
    next_assigned, next_error = allocator.allocate()

    assert error is None
    assert next_error is None
    assert assigned == []
    assert next_assigned == []


def test_allocator_pool_api_allows_api_to_fill_missing_lanes():
    allocator = QueueProxyAllocator(
        proxies=["http://p1:1"],
        api_url="http://proxy-api.example",
        multiplier=3,
        fill_strategy="pool_api",
    )

    assigned, error = allocator.allocate()

    assert error is None
    assert assigned == ["http://p1:1"]


def test_allocator_pool_reports_shortage_without_api_or_direct():
    allocator = QueueProxyAllocator(
        proxies=["http://p1:1"],
        api_url="",
        multiplier=2,
        fill_strategy="pool",
    )

    assigned, error = allocator.allocate()

    assert assigned == ["http://p1:1"]
    assert error == "代理池代理不足"


def test_allocator_pool_api_direct_allows_direct_to_fill_missing_lanes():
    allocator = QueueProxyAllocator(
        proxies=[],
        api_url="",
        multiplier=2,
        fill_strategy="pool_api_direct",
    )

    assigned, error = allocator.allocate()

    assert error is None
    assert assigned == []


def test_fanout_queue_without_limit_uses_all_files_when_proxy_api_exists():
    assert (
        _queue_worker_count(
            file_count=3,
            queue_concurrency_limit=0,
            proxy_count=0,
            fanout_enabled=True,
            proxy_api_url="http://proxy-api.example",
            multiplier=2,
            fill_strategy="pool_api",
        )
        == 3
    )


def test_fanout_queue_pool_strategy_ignores_proxy_api_for_worker_count():
    assert (
        _queue_worker_count(
            file_count=3,
            queue_concurrency_limit=0,
            proxy_count=2,
            fanout_enabled=True,
            proxy_api_url="http://proxy-api.example",
            multiplier=2,
            fill_strategy="pool",
        )
        == 1
    )


def test_fanout_queue_pool_strategy_reuses_proxy_groups_for_more_files():
    assert (
        _queue_worker_count(
            file_count=5,
            queue_concurrency_limit=0,
            proxy_count=2,
            fanout_enabled=True,
            proxy_api_url="",
            multiplier=2,
            fill_strategy="pool",
        )
        == 1
    )


def test_fanout_queue_pool_strategy_clamps_explicit_limit_to_proxy_groups():
    assert (
        _queue_worker_count(
            file_count=5,
            queue_concurrency_limit=5,
            proxy_count=4,
            fanout_enabled=True,
            proxy_api_url="",
            multiplier=2,
            fill_strategy="pool",
        )
        == 2
    )


def test_fanout_queue_without_api_uses_all_files_when_direct_is_allowed():
    assert (
        _queue_worker_count(
            file_count=3,
            queue_concurrency_limit=0,
            proxy_count=0,
            fanout_enabled=True,
            proxy_api_url="",
            multiplier=2,
            fill_strategy="pool_api_direct",
        )
        == 3
    )


def test_fanout_start_error_for_api_without_api_url():
    assert (
        _queue_fanout_start_error(
            proxy_count=10,
            multiplier=2,
            proxy_api_url="",
            fill_strategy="api",
        )
        == "队列多代理抢票需要代理 API。"
    )


def test_fanout_start_allows_pool_api_direct_without_pool_or_api():
    assert (
        _queue_fanout_start_error(
            proxy_count=0,
            multiplier=2,
            proxy_api_url="",
            fill_strategy="pool_api_direct",
        )
        is None
    )


def test_fanout_enabled_is_queue_only():
    assert _is_queue_fanout_enabled(
        proxy_assignment_strategy="queue",
        fanout_enabled=True,
        multiplier=2,
    )
    assert not _is_queue_fanout_enabled(
        proxy_assignment_strategy="balanced",
        fanout_enabled=True,
        multiplier=2,
    )

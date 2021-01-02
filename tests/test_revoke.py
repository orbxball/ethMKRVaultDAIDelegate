import pytest


@pytest.mark.require_network("mainnet-fork")
def test_revoke(dev_ms, live_weth_vault, live_weth_strategy, weth):
    live_weth_vault.revokeStrategy(live_weth_strategy, {"from": dev_ms})
    live_weth_strategy.harvest({"from": dev_ms})

    assert live_weth_vault.totalDebt() == 0
    assert live_weth_vault.totalAssets() == weth.balanceOf(live_weth_vault)

import pytest
from brownie import accounts


@pytest.fixture
def new_strategy(strategist, live_weth_vault, Strategy):
    yield strategist.deploy(Strategy, live_weth_vault)


@pytest.mark.require_network("mainnet-fork")
def test_vault_migration(dev_ms, live_weth_vault, live_weth_strategy, new_strategy):
    live_weth_vault.migrateStrategy(live_weth_strategy, new_strategy, {"from": dev_ms})


@pytest.mark.require_network("mainnet-fork")
def test_migration_through_strategy(dev_ms, live_weth_vault, live_weth_strategy, new_strategy):
    oldAssets = live_weth_strategy.estimatedTotalAssets()
    live_weth_strategy.migrate(new_strategy, {"from": dev_ms})

    assert oldStrategyAssets == new_strategy.estimatedTotalAssets()

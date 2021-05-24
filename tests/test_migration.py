import pytest
from brownie import accounts, config, Contract, Wei


@pytest.fixture
def new_strategy(accounts, strategist, keeper, vault, Strategy, gov):
    strategy = Strategy.deploy(vault, {"from": strategist})
    strategy.setKeeper(keeper)
    yield strategy


def test_vault_migration(gov, vault, strategy, new_strategy):
    oldStrategyAssets = strategy.estimatedTotalAssets()
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})
    assert oldStrategyAssets == new_strategy.estimatedTotalAssets()


def test_migration_through_strategy(gov, vault, strategy, new_strategy):
    oldStrategyAssets = strategy.estimatedTotalAssets()
    strategy.migrate(new_strategy, {"from": gov})
    assert oldStrategyAssets == new_strategy.estimatedTotalAssets()

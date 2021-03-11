import pytest
from brownie import accounts


@pytest.fixture
def new_strategy(accounts, strategist, keeper, vault, Strategy, gov):
    strategy = Strategy.deploy(vault, {"from": strategist})
    strategy.setKeeper(keeper)
    # vault.addStrategy(strategy, 500, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


def test_vault_migration(gov, vault, strategy, new_strategy):
   print(f'strategy: {strategy}, vault: {strategy.vault()}')
   print(f'new_strategy: {new_strategy}, vault: {new_strategy.vault()}')
   vault.migrateStrategy(strategy, new_strategy, {"from": gov})


def test_migration_through_strategy(gov, vault, strategy, new_strategy):
    oldStrategyAssets = strategy.estimatedTotalAssets()
    strategy.migrate(new_strategy, {"from": gov})
    assert oldStrategyAssets == new_strategy.estimatedTotalAssets()

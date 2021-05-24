import pytest
from brownie import chain


def test_change_debt(gov, token, vault, strategy, whale, amount):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": whale})
    vault.deposit(amount, {"from": whale})
    strategy.harvest()
    print(f"debt ratio: {vault.strategies(strategy).dict()['debtRatio']}")
    print(f"strategy assets: {strategy.estimatedTotalAssets()}")
    print(f"vault total assets: {vault.totalAssets()}")

    chain.sleep(86400)
    chain.mine(1)

    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    strategy.harvest()
    print(f"debt ratio: {vault.strategies(strategy).dict()['debtRatio']}")
    print(f"strategy assets: {strategy.estimatedTotalAssets()}")
    print(f"vault total assets: {vault.totalAssets()}")

    chain.sleep(86400)
    chain.mine(1)

    vault.updateStrategyDebtRatio(strategy.address, 10_000, {"from": gov})
    strategy.harvest()
    print(f"debt ratio: {vault.strategies(strategy).dict()['debtRatio']}")
    print(f"strategy assets: {strategy.estimatedTotalAssets()}")
    print(f"vault total assets: {vault.totalAssets()}")

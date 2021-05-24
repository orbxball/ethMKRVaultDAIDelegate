import pytest
from brownie import chain


def test_emergency_exit(gov, vault, strategy, token, whale, amount, dai):
    scale = 10 ** token.decimals()
    # Deposit to the vault
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    assert token.balanceOf(vault.address) == amount
    strategy.harvest({"from": gov})

    dai.transfer(strategy, 1, {"from": gov})

    strategy.setEmergencyExit({"from": gov})
    strategy.harvest({"from": gov})
    print(f"strategy info: {vault.strategies(strategy).dict()}")

    assert vault.totalAssets() == token.balanceOf(vault)

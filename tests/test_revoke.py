import pytest


def test_revoke(gov, vault, strategy, token):
    vault.revokeStrategy(strategy, {"from": gov})
    strategy.harvest({"from": gov})

    assert vault.totalDebt() == 0
    assert vault.totalAssets() == token.balanceOf(vault)

import pytest


def test_emergency_exit(gov, vault, strategy, token):
    strategy.setEmergencyExit({"from": gov})
    strategy.harvest({"from": gov})

    assert vault.totalDebt() == 0
    assert vault.totalAssets() == token.balanceOf(vault)

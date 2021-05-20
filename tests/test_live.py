import pytest
from brownie import accounts, Contract, chain, Wei, Strategy


def test_live(accounts, strategist, gov, Contract):
    strategy = Contract("0x946a03264BBa08d1F90dF1ce0bbD3394c3AB1cfa", owner=gov)

    vault = Contract(strategy.vault(), owner=gov)
    print(vault.strategies(strategy).dict())
    print(strategy.estimatedTotalAssets())
    fixed_strat = Strategy.deploy(vault, {"from": gov})

    vault.setManagementFee(0)
    vault.setPerformanceFee(0)
    vault.updateStrategyPerformanceFee(strategy, 0)

    # revoke, so vault thinks funds are all removed from the strategy (but actually not, 6keth still in the strategy)
    #vault.revokeStrategy(strategy)
    #strategy.harvest()

    print(f"share price: {vault.pricePerShare()}")
    print(f"debt: {strategy.getTotalDebtAmount()}")
    print(f"vault balance: {strategy.balanceOfmVault()}")
    print()

    # migrate to the fixed_strat
    vault.migrateStrategy(strategy, fixed_strat)
    fixed_strat.gulp(strategy.cdpId())
    #vault.updateStrategyDebtRatio(fixed_strat, 3_000)
    #dai = Contract(strategy.dai(), owner=gov )
    #dai.transfer(fixed_strat, 100 *1e18)

    print(f"debt: {strategy.getTotalDebtAmount()}")
    print(f"vault balance: {strategy.balanceOfmVault()}")
    print(f"debt on fixed: {fixed_strat.getTotalDebtAmount()}")
    print(f"vault balance on fixed: {fixed_strat.balanceOfmVault()}")
    print(f"share price: {vault.pricePerShare()}")
    print()

    # repay all debt with migrated yvdai + rescue the locked 6keth in cdp + withdraw weth and let it sit idle on strategy + report it as gain
    fixed_strat.harvest()
    print(f"share price: {vault.pricePerShare()}")
    print(vault.strategies(fixed_strat).dict())
    print()

    # # second harvest should be normal harvest
    fixed_strat.harvest()
    print(f"share price: {vault.pricePerShare()}")
    # print()

    # at the end of the script restore fees
    vault.setManagementFee(40)
    vault.setPerformanceFee(1_000)
    vault.updateStrategyPerformanceFee(fixed_strat, 1_000)

    print()
    fixed_strat.setBorrowCollateralizationRatio(35_000, {"from": gov})
    fixed_strat.harvest().info()
    print(f"share price: {vault.pricePerShare()}")

    print()
    fixed_strat.setBorrowCollateralizationRatio(20_000, {"from": gov})
    fixed_strat.harvest().info()
    print(f"share price: {vault.pricePerShare()}")

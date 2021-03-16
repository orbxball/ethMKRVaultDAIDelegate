from brownie import Contract, ZERO_ADDRESS


def state_of_strategy(strategy, currency, vault):
    scale = 10 ** currency.decimals()
    state = vault.strategies(strategy).dict()
    print(f"\n--- state of {strategy.name()} ---")
    print("Want:", currency.balanceOf(strategy) / scale)
    print("Total assets estimate:", strategy.estimatedTotalAssets() / scale)
    print(f"Total Strategy Debt: {state['totalDebt'] / scale}")
    print(f"Strategy Debt Ratio: {state['debtRatio']}")
    print(f"Total Strategy Gain: {state['totalGain'] / scale}")
    print(f"Total Strategy Loss: {state['totalLoss'] / scale}")
    print("Harvest Trigger:", strategy.harvestTrigger(1000000 * 30 * 1e9))
    print("Tend Trigger:", strategy.tendTrigger(1000000 * 30 * 1e9))
    print("Emergency Exit:", strategy.emergencyExit())
    print(f"Dai Drawn: {strategy.getTotalDebtAmount() / 1e18}")
    print(f"Dai Underlying: {strategy.getUnderlyingDai() / 1e18}")
    print(f"{currency.name()} Locked: {strategy.balanceOfmVault() / scale}")
    print(f"Maker Vault Ratio: {strategy.getmVaultRatio(0) / 10_000}")
    print(f"Draw: {strategy.shouldDraw()} ({strategy.drawAmount() / 1e18})")
    print(f"Repay: {strategy.shouldRepay()} ({strategy.repayAmount() / 1e18})")


def state_of_vault(vault, currency):
    scale = 10 ** currency.decimals()
    print(f"\n--- state of {vault.name()} vault ---")
    print(f"Total Assets: {vault.totalAssets() / scale}")
    print(f"Loose balance in vault: {currency.balanceOf(vault) / scale}")
    print(f"Total Debt: {vault.totalDebt() / scale}")


def harvest_live_vault(vault):
    print(f"Harvesting {vault.name()}")
    gov = vault.governance()
    for i in range(20):
        strat = vault.withdrawalQueue(i)
        if strat == ZERO_ADDRESS:
            break
        strat = Contract(strat)
        print(f"  Harvesting Strategy {strat.name()}")
        strat.harvest({'from': gov})

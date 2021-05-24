from brownie import Wei, reverts, Contract
from useful_methods import state_of_vault, state_of_strategy, harvest_live_vault
import brownie

def test_operation(web3, chain, vault, strategy, token, amount, dai, dai_vault, whale, gov, guardian, strategist):

    # whale approve weth vault to use weth
    token.approve(vault, 2 ** 256 - 1, {"from": whale})

    print(f"cdp id: {strategy.cdpId()}")
    print(f"type of strategy: {type(strategy)} @ {strategy}")
    print(f"type of weth vault: {type(vault)} @ {vault}")
    print()

    # start deposit
    vault.deposit(amount, {"from": whale})
    print(f"whale deposit done with {amount/1e18} weth\n")


    print(f"\n****** Initial Status ******")
    print(f"\n****** {token.symbol()} ******")
    state_of_strategy(strategy, token, vault)
    state_of_vault(vault, token)
    print("\n****** Dai ******")
    state_of_vault(dai_vault, dai)

    print(f"\n****** Harvest {token.symbol()} ******")
    strategy.harvest({"from": strategist})

    print(f"\n****** {token.symbol()} ******")
    state_of_strategy(strategy, token, vault)
    state_of_vault(vault, token)
    print(f"\n****** Dai ******")
    state_of_vault(dai_vault, dai)

    # sleep & realize profit
    print(f"\n****** sleep + realize profit ******")
    harvest_live_vault(dai_vault)
    chain.sleep(86400)
    chain.mine(1)
    # print(f"\n****** Harvest {token.symbol()} ******")
    # strategy.harvest({"from": strategist})

    print(f"\n****** {token.symbol()} ******")
    state_of_strategy(strategy, token, vault)
    state_of_vault(vault, token)
    print("\n****** Dai ******")
    state_of_vault(dai_vault, dai)

    # withdraw
    scale = 10 ** token.decimals()
    print(f"\n****** withdraw {token.symbol()} ******")
    print(f"whale's {token.symbol()} vault share: {vault.balanceOf(whale)/scale}")
    vault.withdraw(amount / 2, {"from": whale})
    print(f"withdraw {amount/2/scale} {token.symbol()} done")
    print(f"whale's {token.symbol()} vault share: {vault.balanceOf(whale)/scale}")

    print(f"\n****** {token.symbol()} ******")
    state_of_strategy(strategy, token, vault)
    state_of_vault(vault, token)
    print(f"\n****** Dai ******")
    state_of_vault(dai_vault, dai)

    # # transfer dai to strategy due to rounding issue
    # dai.transfer(strategy, Wei("1 wei"), {"from": gov})

    # withdraw all
    print(f"\n****** withdraw all {token.symbol()} ******")
    print(f"whale's {token.symbol()} vault share: {vault.balanceOf(whale)/scale}")
    vault.withdraw({"from": whale})
    print(f"withdraw all {token.symbol()}")
    print(f"whale's {token.symbol()} vault share: {vault.balanceOf(whale)/scale}")

    # try call tend
    print(f"\ncall tend")
    strategy.tend()
    print(f"tend done")

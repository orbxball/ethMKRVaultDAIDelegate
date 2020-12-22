from brownie import Wei, reverts
from useful_methods import  genericStateOfVault, genericStateOfStrat
import brownie
# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")


def test_weth_mkrdaidelegate(web3, chain, Vault, Strategy, GuestList, live_dai_vault, live_weth_vault, live_dai_strategy, whale, gov, dai, weth, dev):
    weth.approve(live_weth_vault, 2 ** 256 - 1, {"from": whale} )

    # deploy weth strategy
    strategy = dev.deploy(Strategy, live_weth_vault)
    print('cdp id: {}'.format(strategy.cdpId()))
    print(f'type of strategy: {type(strategy)} @ {strategy}')
    print(f'type of weth vault: {type(live_weth_vault)} @ {live_weth_vault}')

    # activate the strategy from vault view
    live_weth_vault.addStrategy(strategy, 2**256 - 1, 2**256 - 1, 1000, {"from": gov})
    print(f'credit of strategy: {live_weth_vault.creditAvailable(strategy)}')

    # uplift the dai vault deposit limit for weth strategy
    live_dai_vault.setDepositLimit(1_000_000*1e18, {'from': gov})

    # start deposit
    deposit_amount = Wei('10 ether')
    live_weth_vault.deposit(deposit_amount, {"from": whale})

    # let bouncer to put weth strategy in the yvdai guestlist
    guest_list = GuestList.at(live_dai_vault.guestList())
    print(f'yvdai guest list: {guest_list}')
    guest_list.invite_guest(strategy, {'from': dev})
    print(f'successfully added: {guest_list.authorized(strategy, 1e18)}')


    print("\n****** Harvest Weth ******")
    #print(f'price: {strategy._getPrice({"from": dev})} ')
    strategy.harvest({'from': dev})

    print("\n****** Weth ******")
    genericStateOfStrat(strategy, weth, live_weth_vault)
    genericStateOfVault(live_weth_vault, weth)
    print("\n****** Dai ******")
    genericStateOfStrat(live_dai_strategy, dai, live_dai_vault)
    genericStateOfVault(live_dai_vault, dai)


    print("\n****** Harvest Dai ******")
    live_dai_strategy.harvest({'from': dev})

    print("\n****** Weth ******")
    genericStateOfStrat(strategy, weth, live_weth_vault)
    genericStateOfVault(live_weth_vault, weth)
    print("\n****** Dai ******")
    genericStateOfStrat(live_dai_strategy, dai, live_dai_vault)
    genericStateOfVault(live_dai_vault, dai)

    # call tend
    print('\ncall tend')
    strategy.tend()
    print('tend done')


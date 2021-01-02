# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")
from brownie import Wei, reverts
from useful_methods import genericStateOfVault, genericStateOfStrat
import brownie

def test_weth_mkrdaidelegate(web3, chain, Vault, Strategy, GuestList, dai_vault, weth_vault, dai_strategy, whale, gov, guardian, dai, weth, dev):

    # whale approve weth vault to use weth
    weth.approve(weth_vault, 2 ** 256 - 1, {"from": whale} )

    # deploy weth strategy
    strategy = dev.deploy(Strategy, weth_vault)
    print('cdp id: {}'.format(strategy.cdpId()))
    print(f'type of strategy: {type(strategy)} @ {strategy}')
    print(f'type of weth vault: {type(weth_vault)} @ {weth_vault}')
    print()

    # activate the strategy from vault view
    weth_vault.addStrategy(strategy, 1e27, 1e27, 1000, {"from": guardian})
    print(f'credit of strategy: {weth_vault.creditAvailable(strategy)}')

    # uplift the dai vault deposit limit for weth strategy
    dai_vault.setDepositLimit(1_000_000*1e18, {'from': gov})

    # start deposit
    deposit_amount = Wei('10 ether')
    weth_vault.deposit(deposit_amount, {"from": whale})
    print(f'whale deposit done with {deposit_amount/1e18} weth\n')

    # let bouncer to put weth strategy in the yvdai guestlist
    guest_list = GuestList.at(dai_vault.guestList())
    print(f'yvdai guest list: {guest_list}')
    guest_list.invite_guest(strategy, {'from': dev})
    print(f'successfully added: {guest_list.authorized(strategy, 1e18)}\n')


    print("\n****** Initial Status ******")
    print("\n****** Weth ******")
    genericStateOfStrat(strategy, weth, weth_vault)
    genericStateOfVault(weth_vault, weth)
    print("\n****** Dai ******")
    genericStateOfStrat(dai_strategy, dai, dai_vault)
    genericStateOfVault(dai_vault, dai)


    print("\n****** Harvest Weth ******")
    #print(f'price: {strategy._getPrice({"from": dev})} ')
    strategy.harvest({'from': dev})

    print("\n****** Weth ******")
    genericStateOfStrat(strategy, weth, weth_vault)
    genericStateOfVault(weth_vault, weth)
    print("\n****** Dai ******")
    genericStateOfStrat(dai_strategy, dai, dai_vault)
    genericStateOfVault(dai_vault, dai)


    print("\n****** Harvest Dai ******")
    dai_strategy.harvest({'from': dev})

    print("\n****** Weth ******")
    genericStateOfStrat(strategy, weth, weth_vault)
    genericStateOfVault(weth_vault, weth)
    print("\n****** Dai ******")
    genericStateOfStrat(dai_strategy, dai, dai_vault)
    genericStateOfVault(dai_vault, dai)

    # withdraw weth
    print('\n****** withdraw weth ******')
    print(f'whale\'s weth vault share: {weth_vault.balanceOf(whale)/1e18}')
    weth_vault.withdraw(Wei('1 ether'), {"from": whale})
    print(f'withdraw 1 ether done')
    print(f'whale\'s weth vault share: {weth_vault.balanceOf(whale)/1e18}')

    # withdraw all weth
    print('\n****** withdraw all weth ******')
    print(f'whale\'s weth vault share: {weth_vault.balanceOf(whale)/1e18}')
    weth_vault.withdraw({"from": whale})
    print(f'withdraw all weth')
    print(f'whale\'s weth vault share: {weth_vault.balanceOf(whale)/1e18}')

    # try call tend
    print('\ncall tend')
    strategy.tend()
    print('tend done')

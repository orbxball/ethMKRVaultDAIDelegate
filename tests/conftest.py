import pytest
from brownie import Wei, config


@pytest.fixture
def vault(gov, rewards, guardian, currency, pm):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault, currency, gov, rewards, "", "")
    yield vault

@pytest.fixture
def strategy(strategist, keeper, vault, Strategy):
    strategy = strategist.deploy(Strategy, vault)
    strategy.setKeeper(keeper)
    yield strategy

@pytest.fixture
def Vault(pm):
    Vault = pm(config["dependencies"][0]).Vault
    yield Vault


@pytest.fixture
def weth(interface):
    yield interface.ERC20('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2')

@pytest.fixture
def dai(interface):
    yield interface.ERC20('0x6B175474E89094C44Da98b954EedeAC495271d0F')

@pytest.fixture
def live_weth_vault(Vault):
    yield Vault.at('0x6392e8fa0588CB2DCb7aF557FdC9D10FDe48A325')

@pytest.fixture
def live_dai_vault(Vault):
    yield Vault.at('0xBFa4D8AA6d8a379aBFe7793399D3DdaCC5bBECBB')

@pytest.fixture
def live_weth_strategy(Strategy):
    yield Strategy.at('0x2476eC85e55625Eb658CAFAFe5fdc0FAE2954C85')

@pytest.fixture
def live_dai_strategy(Strategy):
    # GenericLevCompFarm
    yield Strategy.at('0x001F751cdfee02e2F0714831bE2f8384db0F71a2')


@pytest.fixture(scope='session')
def dev(accounts):
    # Sam's dev account
    yield accounts.at('0xC3D6880fD95E06C816cB030fAc45b3ffe3651Cb0', force=True)

@pytest.fixture
def andre(accounts):
    # Andre, giver of tokens, and maker of yield
    yield accounts[0]

@pytest.fixture
def token(andre, Token):
    yield andre.deploy(Token)

@pytest.fixture
def gov(accounts):
    yield accounts.at('0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52', force=True)


@pytest.fixture
def dev_ms(accounts):
    yield accounts.at('0x846e211e8ba920B353FB717631C015cf04061Cc9', force=True)


@pytest.fixture
def rewards(gov):
    yield gov  # TODO: Add rewards contract

@pytest.fixture
def guardian(accounts):
    # yield accounts.at('0x846e211e8ba920b353fb717631c015cf04061cc9', force=True)
    yield accounts[2]

@pytest.fixture
def vault(gov, rewards, guardian, token, Vault):
    vault = guardian.deploy(Vault, token, gov, rewards, "", "")
    yield vault

@pytest.fixture
def strategist(accounts):
    # You! Our new Strategist!
    yield accounts[3]

@pytest.fixture
def keeper(accounts):
    # This is our trusty bot!
    yield accounts[4]

@pytest.fixture
def whale(accounts, history, web3):
    # binance7 wallet
    #acc = accounts.at('0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8', force=True)

    # binance8 wallet
    #acc = accounts.at('0xf977814e90da44bfa03b6295a0616a897441acec', force=True)

    # weth whale
    acc = accounts.at('0xee2826453A4Fd5AfeB7ceffeEF3fFA2320081268', force=True)
    yield acc

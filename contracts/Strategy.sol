// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/maker/Maker.sol";
import "../interfaces/yearn/yVault.sol";
import "../interfaces/uniswap/Uni.sol";


contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // want = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public cdp_manager = address(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    address public vat = address(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    address public mcd_join_eth_a = address(0x2F0b23f53734252Bda2277357e97e1517d6B042A);
    address public mcd_join_dai = address(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    address public mcd_spot = address(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
    address public jug = address(0x19c0976f590D67707E62397C87829d896Dc0f1F1);
    address public auto_line = address(0xC7Bdd1F2B16447dcf3dE045C4a039A60EC2f0ba3);

    address public eth_price_oracle = address(0xCF63089A8aD2a9D8BD6Bb8022f3190EB7e1eD0f1);
    address constant public yvdai = address(0x19D3364A399d251E894aC732651be8B0E4e85001);

    address constant public uniswap = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant public sushiswap = address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    uint constant public DENOMINATOR = 10000;
    bytes32 constant public ilk = "ETH-A";

    uint public c;
    uint public c_safe;
    uint public buffer;
    uint public cdpId;
    address public dex;

    constructor(address _vault) public BaseStrategy(_vault) {
        minReportDelay = 1 days;
        maxReportDelay = 3 days;
        profitFactor = 1000;
        c = 20000;
        c_safe = 40000;
        buffer = 500;
        dex = sushiswap;
        cdpId = ManagerLike(cdp_manager).open(ilk, address(this));
        _approveAll();
    }

    function _approveAll() internal {
        want.approve(mcd_join_eth_a, uint(-1));
        IERC20(dai).approve(mcd_join_dai, uint(-1));
        VatLike(vat).hope(mcd_join_dai);
        IERC20(dai).approve(yvdai, uint(-1));
        IERC20(dai).approve(uniswap, uint(-1));
        IERC20(dai).approve(sushiswap, uint(-1));
    }

    function name() external view override returns (string memory) {
        return "StrategyMakerETHDAIDelegate";
    }

    function setBorrowCollateralizationRatio(uint _c) external onlyAuthorized {
        c = _c;
    }

    function setWithdrawCollateralizationRatio(uint _c_safe) external onlyAuthorized {
        c_safe = _c_safe;
    }

    function setBuffer(uint _buffer) external onlyAuthorized {
        buffer = _buffer;
    }

    function setOracle(address _oracle) external onlyGovernance {
        eth_price_oracle = _oracle;
    }

    // optional
    function setMCDValue(
        address _manager,
        address _ethAdapter,
        address _daiAdapter,
        address _spot,
        address _jug
    ) external onlyGovernance {
        cdp_manager = _manager;
        vat = ManagerLike(_manager).vat();
        mcd_join_eth_a = _ethAdapter;
        mcd_join_dai = _daiAdapter;
        mcd_spot = _spot;
        jug = _jug;
    }

    function switchDex(bool isUniswap) external onlyAuthorized {
        if (isUniswap) dex = uniswap;
        else dex = sushiswap;
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceOfmVault());
    }

    function balanceOfWant() public view returns (uint) {
        return want.balanceOf(address(this));
    }

    function balanceOfmVault() public view returns (uint) {
        address urnHandler = ManagerLike(cdp_manager).urns(cdpId);
        return VatLike(vat).urns(ilk, urnHandler).ink;
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        _profit = want.balanceOf(address(this));
        uint v = getUnderlyingDai();
        uint d = getTotalDebtAmount();
        if (v > d) {
            _withdrawDai(v.sub(d));
            _swap(IERC20(dai).balanceOf(address(this)));
            
            _profit = want.balanceOf(address(this));
        }

        if (_debtOutstanding > 0) {
            (_debtPayment, _loss) = liquidatePosition(_debtOutstanding);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        JugLike(jug).drip(ilk);  // update stability fee rate accumulator
        DssAutoLine(auto_line).exec(ilk);  // bump available debt ceiling

        _deposit();
        if (shouldDraw()) draw();
        else if (shouldRepay()) repay();
    }

    function _deposit() internal {
        uint _token = want.balanceOf(address(this));
        if (_token == 0) return;

        uint p = _getPrice();
        uint _draw = _token.mul(p).mul(DENOMINATOR).div(c).div(1e18);
        _draw = _adjustDrawAmount(_draw);
        if (_draw == 0) return;

        _lockWETHAndDrawDAI(_token, _draw);
        yVault(yvdai).deposit();
    }

    function _getPrice() internal view returns (uint p) {
        (uint _read,) = OSMedianizer(eth_price_oracle).read();
        (uint _foresight,) = OSMedianizer(eth_price_oracle).foresight();
        p = _foresight < _read ? _foresight : _read;
    }

    function _adjustDrawAmount(uint amount) internal view returns (uint _available) {
        // adjust max amount of dai available to draw
        VatLike.Ilk memory _ilk = VatLike(vat).ilks(ilk);
        uint _debt = _ilk.Art.mul(_ilk.rate).add(1e27);  // [rad]
        if (_debt > _ilk.line) return 0;  // avoid Vat/ceiling-exceeded
        _available = _ilk.line.sub(_debt).div(1e27);
        if (_available.mul(1e27) < _ilk.dust) return 0;  // avoid Vat/dust
        return _available < amount ? _available : amount;
    }

    function _lockWETHAndDrawDAI(uint wad, uint wadD) internal {
        address urn = ManagerLike(cdp_manager).urns(cdpId);
        if (wad > 0) { GemJoinLike(mcd_join_eth_a).join(urn, wad); }
        ManagerLike(cdp_manager).frob(cdpId, toInt(wad), _getDrawDart(urn, wadD));
        ManagerLike(cdp_manager).move(cdpId, address(this), wadD.mul(1e27));
        if (wadD > 0) { DaiJoinLike(mcd_join_dai).exit(address(this), wadD); }
    }

    function _getDrawDart(address urn, uint wad) internal returns (int dart) {
        uint rate = VatLike(vat).ilks(ilk).rate;
        uint _dai = VatLike(vat).dai(urn);

        // If there was already enough DAI in the vat balance, just exits it without adding more debt
        if (_dai < wad.mul(1e27)) {
            dart = toInt(wad.mul(1e27).sub(_dai).div(rate));
            dart = uint(dart).mul(rate) < wad.mul(1e27) ? dart + 1 : dart;
        }
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    function shouldDraw() public view returns (bool) {
        // buffer to avoid deposit/rebalance loops
        return (getmVaultRatio(0) > c.mul(1e2).mul(DENOMINATOR).div((DENOMINATOR.sub(buffer))));
    }

    function drawAmount() public view returns (uint) {
        // amount to draw to reach target ratio not accounting for debt ceiling
        uint _safe = c.mul(1e2);
        uint _current = getmVaultRatio(0);
        if (_current > DENOMINATOR.mul(c_safe).mul(1e2)) {
            _current = DENOMINATOR.mul(c_safe).mul(1e2);
        }
        if (_current > _safe) {
            uint d = getTotalDebtAmount();
            uint diff = _current.sub(_safe);
            return d.mul(diff).div(_safe);
        }
        return 0;
    }

    function draw() internal {
        uint _drawD = _adjustDrawAmount(drawAmount());
        if (_drawD > 0) {
            _lockWETHAndDrawDAI(0, _drawD);
            yVault(yvdai).deposit();
        }
    }

    function shouldRepay() public view returns (bool) {
        // buffer to avoid deposit/rebalance loops
        return (getmVaultRatio(0) < c.mul(1e2).mul(DENOMINATOR).div((DENOMINATOR.add(buffer))));
    }
    
    function repayAmount() public view returns (uint) {
        uint _safe = c.mul(1e2);
        uint _current = getmVaultRatio(0);
        if (_current < _safe) {
            uint d = getTotalDebtAmount();
            uint diff = _safe.sub(_current);
            return d.mul(diff).div(_safe);
        }
        return 0;
    }
    
    function repay() internal {
        uint _free = repayAmount();
        if (_free > 0) {
            _withdrawDai(_free);
            _freeWETHandWipeDAI(0, IERC20(dai).balanceOf(address(this)));
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        if (getTotalDebtAmount() != 0 && 
            getmVaultRatio(_amountNeeded) < c_safe.mul(1e2)) {
            uint p = _getPrice();
            _withdrawDai(_amountNeeded.mul(p).div(1e18));
        }
        
        _freeWETHandWipeDAI(_amountNeeded, IERC20(dai).balanceOf(address(this)));
        _liquidatedAmount = _amountNeeded;
    }

    function _freeWETHandWipeDAI(uint wad, uint wadD) internal {
        address urn = ManagerLike(cdp_manager).urns(cdpId);
        if (wadD > 0) { DaiJoinLike(mcd_join_dai).join(urn, wadD); }
        ManagerLike(cdp_manager).frob(cdpId, -toInt(wad), _getWipeDart(VatLike(vat).dai(urn), urn));
        ManagerLike(cdp_manager).flux(cdpId, address(this), wad);
        if (wad > 0) { GemJoinLike(mcd_join_eth_a).exit(address(this), wad); }
    }

    function _getWipeDart(
        uint _dai,
        address urn
    ) internal view returns (int dart) {
        uint rate = VatLike(vat).ilks(ilk).rate;
        uint art = VatLike(vat).urns(ilk, urn).art;

        dart = toInt(_dai / rate);
        dart = uint(dart) <= art ? - dart : - toInt(art);
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    function tendTrigger(uint256 callCost) public override view returns (bool) {
        if (balanceOfmVault() == 0) return false;
        else return shouldRepay() || (shouldDraw() && _adjustDrawAmount(drawAmount()) > callCost.mul(_getPrice()).mul(profitFactor));
    }

    function prepareMigration(address _newStrategy) internal override {
        ManagerLike(cdp_manager).cdpAllow(cdpId, _newStrategy, 1);
        IERC20(yvdai).safeTransfer(_newStrategy, IERC20(yvdai).balanceOf(address(this)));
    }

    function allow(address dst) external onlyGovernance {
        ManagerLike(cdp_manager).cdpAllow(cdpId, dst, 1);
    }

    function gulp(uint srcCdp) external onlyGovernance {
        ManagerLike(cdp_manager).shift(srcCdp, cdpId);
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = yvdai;
        protected[1] = dai;
        return protected;
    }

    function forceRebalance(uint _amount) external onlyAuthorized {
        if (_amount > 0) _withdrawDai(_amount);
        _freeWETHandWipeDAI(0, IERC20(dai).balanceOf(address(this)));
    }

    function getTotalDebtAmount() public view returns (uint) {
        address urnHandler = ManagerLike(cdp_manager).urns(cdpId);
        uint art = VatLike(vat).urns(ilk, urnHandler).art;
        uint rate = VatLike(vat).ilks(ilk).rate;
        return art.mul(rate).div(1e27);
    }

    function getmVaultRatio(uint amount) public view returns (uint) {
        uint spot; // ray
        uint liquidationRatio; // ray
        uint denominator = getTotalDebtAmount();

        if (denominator == 0) {
            return uint(-1);
        }

        spot = VatLike(vat).ilks(ilk).spot;
        liquidationRatio = SpotLike(mcd_spot).ilks(ilk).mat;
        uint delayedCPrice = spot.mul(liquidationRatio).div(1e27); // ray

        uint _balance = balanceOfmVault();
        if (_balance < amount) {
            _balance = 0;
        } else {
            _balance = _balance.sub(amount);
        }

        uint numerator = _balance.mul(delayedCPrice).div(1e18); // ray
        return numerator.div(denominator).div(1e3);
    }

    function getUnderlyingDai() public view returns (uint) {
        return IERC20(yvdai).balanceOf(address(this))
                .mul(yVault(yvdai).pricePerShare())
                .div(1e18);
    }

    function _withdrawDai(uint _amount) internal returns (uint) {
        uint _shares = _amount
                        .mul(1e18)
                        .div(yVault(yvdai).pricePerShare());

        if (_shares > IERC20(yvdai).balanceOf(address(this))) {
            _shares = IERC20(yvdai).balanceOf(address(this));
        }

        uint _before = IERC20(dai).balanceOf(address(this));
        yVault(yvdai).withdraw(_shares);
        uint _after = IERC20(dai).balanceOf(address(this));
        return _after.sub(_before);
    }

    function _swap(uint _amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = dai;
        path[1] = address(want);

        // approve dex to use dai
        Uni(dex).swapExactTokensForTokens(_amountIn, 0, path, address(this), now);
    }
}

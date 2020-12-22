pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/utils/Address.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/maker/Maker.sol";
import "../interfaces/UniswapInterfaces/Uni.sol";
import "@yearnvaults/contracts/BaseStrategy.sol";


interface yVault is VaultAPI {
    function pricePerShare() external view returns (uint);
    function deposit(uint) external returns (uint);
    function withdraw(uint) external returns (uint);
}

/* Need to override
 * [V] name()
 * [V] estimatedTotalAssets()
 * [V] prepareReturn(uint256 _debtOutstanding)
 * [V] adjustPosition(uint256 _debtOutstanding)
 * [V] exitPosition(uint256 _debtOutstanding)
 * [V] distributeRewards(uint256 _shares)
 * [V] tendTrigger(uint256 callCost)
 * [V] harvestTrigger(uint256 callCost)
 * [V] liquidatePosition(uint256 _amountNeeded)
 * [V] prepareMigration(address _newStrategy)
 * [V] protectedTokens()
 */

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public cdp_manager = address(0x5ef30b9986345249bc32d8928B7ee64DE9435E39);
    address public vat = address(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    address public mcd_join_eth_a = address(0x2F0b23f53734252Bda2277357e97e1517d6B042A);
    address public mcd_join_dai = address(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    address public mcd_spot = address(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);
    address public jug = address(0x19c0976f590D67707E62397C87829d896Dc0f1F1);

    address public eth_price_oracle = address(0xCF63089A8aD2a9D8BD6Bb8022f3190EB7e1eD0f1);
    address constant public yvdai = address(0xBFa4D8AA6d8a379aBFe7793399D3DdaCC5bBECBB);

    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // DEFAULT VALUE
    // uint256 public minReportDelay = 86400;
    // uint256 public profitFactor = 100;
    // uint256 public debtThreshold = 0;

    uint public c = 20000;
    uint public c_safe = 40000;
    uint public buffer = 500;

    uint constant public DENOMINATOR = 10000;
    bytes32 constant public ilk = "ETH-A";

    uint public cdpId;

    constructor(address _vault) public BaseStrategy(_vault) {
        cdpId = ManagerLike(cdp_manager).open(ilk, address(this));
        _approveAll();
    }

    function name() external override pure returns (string memory) {
        return "StrategyMKRVaultDAIDelegate";
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

    function prepareMigration(address _newStrategy) internal override {
        allow(_newStrategy);
        IERC20(yvdai).safeTransfer(_newStrategy, IERC20(yvdai).balanceOf(address(this)));
    }

    function allow(address dst) public onlyAuthorized {
        ManagerLike(cdp_manager).cdpAllow(cdpId, dst, 1);
    }

    function _approveAll() internal {
        IERC20(want).approve(mcd_join_eth_a, uint(-1));
        IERC20(dai).approve(mcd_join_dai, uint(-1));
        VatLike(vat).hope(mcd_join_dai);
        IERC20(dai).approve(yvdai, uint(-1));
        IERC20(dai).approve(unirouter, uint(-1));
    }

    function protectedTokens() internal override view returns (address[] memory) {
        address[] memory protected = new address[](2);
        protected[0] = yvdai;
        protected[1] = dai;
        return protected;
    }

    function distributeRewards() internal override {
        // Transfer 100% of newly-minted shares awarded to this contract to the rewards address.
        vault.transfer(rewards, vault.balanceOf(address(this)));
    }

    function _deposit() internal {
        uint _token = IERC20(want).balanceOf(address(this));
        if (_token > 0) {
            uint p = _getPrice();
            uint _draw = _token.mul(p).mul(DENOMINATOR).div(c).div(1e18);
            // approve adapter to use token amount
            require(_checkDebtCeiling(_draw), "debt ceiling is reached!");
            _lockWETHAndDrawDAI(_token, _draw);

            // approve yvdai use DAI
            yVault(yvdai).deposit(IERC20(dai).balanceOf(address(this)));
        }
    }

    function _getPrice() internal view returns (uint p) {
        (uint _read,) = OSMedianizer(eth_price_oracle).read();
        (uint _foresight,) = OSMedianizer(eth_price_oracle).foresight();
        p = _foresight < _read ? _foresight : _read;
    }

    function _checkDebtCeiling(uint _amt) internal view returns (bool) {
        (,,,uint _line,) = VatLike(vat).ilks(ilk);
        uint _debt = getTotalDebtAmount().add(_amt);
        if (_line.div(1e27) < _debt) { return false; }
        return true;
    }

    function _lockWETHAndDrawDAI(uint wad, uint wadD) internal {
        address urn = ManagerLike(cdp_manager).urns(cdpId);
        if (wad > 0) { GemJoinLike(mcd_join_eth_a).join(urn, wad); }
        ManagerLike(cdp_manager).frob(cdpId, toInt(wad), _getDrawDart(urn, wadD));
        ManagerLike(cdp_manager).move(cdpId, address(this), wadD.mul(1e27));
        if (wadD > 0) { DaiJoinLike(mcd_join_dai).exit(address(this), wadD); }
    }

    function _getDrawDart(address urn, uint wad) internal returns (int dart) {
        uint rate = JugLike(jug).drip(ilk);
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
        (, uint rate,,,) = VatLike(vat).ilks(ilk);
        (, uint art) = VatLike(vat).urns(ilk, urn);

        dart = toInt(_dai / rate);
        dart = uint(dart) <= art ? - dart : - toInt(art);
    }

    function exitPosition(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        ) {
        (_profit, _loss, _debtPayment) = prepareReturn(_debtOutstanding);
        _withdrawAll();
        uint _dai = IERC20(dai).balanceOf(address(this));
        if (_dai > 0) _swap(_dai);
        _debtPayment = _debtPayment.add(IERC20(want).balanceOf(address(this)));
    }

    function _withdrawAll() internal {
        yVault(yvdai).withdraw(IERC20(yvdai).balanceOf(address(this))); // get Dai
        _freeWETHandWipeDAI(balanceOfmVault(), getTotalDebtAmount().add(1)); // in case of edge case
    }

    function estimatedTotalAssets() public override view returns (uint256) {
        return balanceOfWant().add(balanceOfmVault()).add(realizedReturn());
    }

    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfmVault() public view returns (uint) {
        uint ink;
        address urnHandler = ManagerLike(cdp_manager).urns(cdpId);
        (ink,) = VatLike(vat).urns(ilk, urnHandler);
        return ink;
    }

    function realizedReturn() public view returns(uint _profit) {
        uint v = getUnderlyingDai();
        uint d = getTotalDebtAmount();
        if (v > d) _profit = (v.sub(d)).mul(1e18).div(_getPrice());
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        ) {
        _profit = IERC20(weth).balanceOf(address(this));
        uint v = getUnderlyingDai();
        uint d = getTotalDebtAmount();
        if (v > d) {
            _withdrawDaiMost(v.sub(d));
            _swap(IERC20(dai).balanceOf(address(this)));
            
            _profit = IERC20(want).balanceOf(address(this));
        }

        if (_debtOutstanding > 0) {
            _debtPayment = liquidatePosition(_debtOutstanding);
        }
    }

    function tendTrigger(uint256 callCost) public override view returns (bool) {
        // We usually don't need tend, but if there are positions that need active maintainence,
        // overriding this function is how you would signal for that
        return shouldDraw() || shouldRepay();
    }

    function harvestTrigger(uint256 callCost) public override view returns (bool) {
        StrategyParams memory params = vault.strategies(address(this));

        // Should not trigger if Strategy is not activated
        if (params.activation == 0) return false;

        // Should trigger if hasn't been called in a while
        if (block.timestamp.sub(params.lastReport) >= minReportDelay) return true;

        // If some amount is owed, pay it back
        // NOTE: Since debt is adjusted in step-wise fashion, it is appropriate
        //       to always trigger here, because the resulting change should be
        //       large (might not always be the case).
        uint256 outstanding = vault.debtOutstanding();
        if (outstanding > 0) return true;

        // Check for profits and losses
        uint256 total = estimatedTotalAssets();
        // Trigger if we have a loss to report
        if (total.add(debtThreshold) < params.totalDebt) return true;

        uint256 profit = 0;
        if (total > params.totalDebt) profit = total.sub(params.totalDebt); // We've earned a profit!

        // Otherwise, only trigger if it "makes sense" economically (gas cost
        // is <N% of value moved)
        uint256 credit = vault.creditAvailable();
        return (profitFactor.mul(callCost) < credit.add(profit));
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _amountFreed) {
        uint _wipe = 0;
        if (getTotalDebtAmount() != 0 && 
            getmVaultRatio(_amountNeeded) < c_safe.mul(1e2)) {
            uint p = _getPrice();
            _wipe = _withdrawDaiLeast(_amountNeeded.mul(p).div(1e18));
        }
        
        _freeWETHandWipeDAI(_amountNeeded, _wipe);
        _amountFreed = _amountNeeded;
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (shouldDraw()) draw();
        else if (shouldRepay()) repay();
        _deposit();
    }

    function shouldDraw() public view returns (bool) {
        // 5% buffer to avoid deposit/rebalance loops
        return (getmVaultRatio(0) > c.mul(1e2).mul(DENOMINATOR).div((DENOMINATOR.sub(buffer))));
    }

    function drawAmount() public view returns (uint) {
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
        uint _drawD = drawAmount();
        if (_drawD > 0) {
            _lockWETHAndDrawDAI(0, _drawD);
            yVault(yvdai).deposit(IERC20(dai).balanceOf(address(this)));
        }
    }

    function shouldRepay() public view returns (bool) {
        // 5% buffer to avoid deposit/rebalance loops
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
        uint free = repayAmount();
        if (free > 0) {
            _freeWETHandWipeDAI(0, _withdrawDaiLeast(free));
        }
    }
    
    function forceRebalance(uint _amount) external onlyAuthorized {
        _freeWETHandWipeDAI(0, _withdrawDaiLeast(_amount));
    }

    function getTotalDebtAmount() public view returns (uint) {
        uint art;
        uint rate;
        address urnHandler = ManagerLike(cdp_manager).urns(cdpId);
        (,art) = VatLike(vat).urns(ilk, urnHandler);
        (,rate,,,) = VatLike(vat).ilks(ilk);
        return art.mul(rate).div(1e27);
    }

    function getmVaultRatio(uint amount) public view returns (uint) {
        uint spot; // ray
        uint liquidationRatio; // ray
        uint denominator = getTotalDebtAmount();

        if (denominator == 0) {
            return uint(-1);
        }

        (,,spot,,) = VatLike(vat).ilks(ilk);
        (,liquidationRatio) = SpotLike(mcd_spot).ilks(ilk);
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

    function _withdrawDaiMost(uint _amount) internal returns (uint) {
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

    function _withdrawDaiLeast(uint _amount) internal returns (uint) {
        uint _shares = _amount
                        .mul(1e18)
                        .div(yVault(yvdai).pricePerShare())
                        .mul(DENOMINATOR)
                        .div(DENOMINATOR.sub(buffer.div(10)));

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
        path[0] = address(dai);
        path[1] = address(want);

        // approve unirouter to use dai
        Uni(unirouter).swapExactTokensForTokens(_amountIn, 0, path, address(this), now.add(1 days));
    }
}
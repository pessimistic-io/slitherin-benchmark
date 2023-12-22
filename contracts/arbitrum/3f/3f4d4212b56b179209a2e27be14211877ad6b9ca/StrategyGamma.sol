// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IStrategyHelperUniswapV3} from "./IStrategyHelper.sol";
import {IUniProxy, IHypervisor, IQuoter} from "./IGamma.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {IERC20} from "./IERC20.sol";
import {TickMath} from "./TickMath.sol";
import {Strategy} from "./Strategy.sol";

contract StrategyGamma is Strategy {
    IStrategyHelperUniswapV3 public immutable strategyHelperUniswapV3;
    IUniProxy public immutable uniProxy;
    IQuoter public immutable quoter;
    IHypervisor public immutable hypervisor;
    bytes public pathToLp; // UniV3 path from targetAsset to other asset
    address public targetAsset;
    uint32 public twapPeriod = 1800;
    string public name;

    error WrongTargetAsset();
    error PriceSlipped();

    constructor(
        address _strategyHelper,
        address _strategyHelperUniswapV3,
        address _uniProxy,
        address _quoter,
        address _hypervisor,
        address _targetAsset,
        bytes memory _pathToLp
    ) Strategy(_strategyHelper) {
        strategyHelperUniswapV3 = IStrategyHelperUniswapV3(_strategyHelperUniswapV3);
        uniProxy = IUniProxy(_uniProxy);
        quoter = IQuoter(_quoter);
        hypervisor = IHypervisor(_hypervisor);
        targetAsset = _targetAsset;
        pathToLp = _pathToLp;
        name = string(abi.encodePacked("Gamma ", hypervisor.token0().symbol(), "/", hypervisor.token1().symbol()));

        if (_targetAsset != address(hypervisor.token0()) && _targetAsset != address(hypervisor.token1())) {
            revert WrongTargetAsset();
        }
    }

    function setPathToLp(bytes calldata newPathToLp) external auth {
        pathToLp = newPathToLp;
    }

    function setTwapPeriod(uint32 newTwapPeriod) external auth {
        twapPeriod = newTwapPeriod;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        pull(IERC20(ast), msg.sender, amt);
        address tgtAst = targetAsset;
        uint256 slp = getSlippage(dat);
        uint256 tma = totalManagedAssets();

        IERC20(ast).approve(address(strategyHelper), amt);
        strategyHelper.swap(ast, tgtAst, amt, slp, address(this));

        uint256 liq;
        {
            uint256 tgtAmt = IERC20(tgtAst).balanceOf(address(this));
            (uint256 amt0, uint256 amt1) = quoteAndSwap(tgtAst, tgtAmt, slp);
            address hyp = address(hypervisor);
            hypervisor.token0().approve(hyp, amt0);
            hypervisor.token1().approve(hyp, amt1);
            liq = uniProxy.deposit(amt0, amt1, address(this), hyp, [uint256(0), 0, 0, 0]);
        }

        uint256 val = valueLiquidity() * liq / totalManagedAssets();
        if (val < strategyHelper.value(ast, amt) * (10000 - slp) / 10000) revert PriceSlipped();
        return tma == 0 ? liq : liq * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 tma = totalManagedAssets();
        uint256 amt = (sha * tma) / totalShares;
        uint256 val = valueLiquidity() * amt / tma;
        (uint256 amt0, uint256 amt1) = hypervisor.withdraw(amt, address(this), address(this), [uint256(0), 0, 0, 0]);

        address strategyHelperAddress = address(strategyHelper);
        hypervisor.token0().approve(strategyHelperAddress, amt0);
        hypervisor.token1().approve(strategyHelperAddress, amt1);

        uint256 bal;
        uint256 slp = getSlippage(dat);
        bal += strategyHelper.swap(address(hypervisor.token0()), ast, amt0, slp, msg.sender);
        bal += strategyHelper.swap(address(hypervisor.token1()), ast, amt1, slp, msg.sender);

        if (strategyHelper.value(ast, bal) < val * (10000 - slp) / 10000) revert PriceSlipped();
        return bal;
    }

    // Noop. Gamma handles autocompounding
    function _earn() internal override {}

    function _exit(address str) internal override {
        push(IERC20(address(hypervisor)), str, totalManagedAssets());
    }

    // Noop. No staking, just hold already transdered hypervisor erc20
    function _move(address old) internal override {}

    function _rate(uint256 sha) internal view override returns (uint256) {
        return sha * valueLiquidity() / totalShares;
    }

    function quoteAddLiquidity(uint256 amt, address trgtAst, bytes memory path) private returns (uint256, uint256) {
        uint256 lp0Amt = amt / 2;
        uint256 lp1Amt = amt - lp0Amt;
        uint256 out0 = lp0Amt;
        uint256 out1 = lp1Amt;
        bytes memory path0 = trgtAst != address(hypervisor.token0()) ? path : bytes("");
        bytes memory path1 = trgtAst != address(hypervisor.token1()) ? path : bytes("");

        if (path0.length > 0) {
            out0 = quoter.quoteExactInput(path0, lp0Amt);
        }
        if (path1.length > 0) {
            out1 = quoter.quoteExactInput(path1, lp1Amt);
        }

        (uint256 start, uint256 end) =
            uniProxy.getDepositAmount(address(hypervisor), address(hypervisor.token0()), out0);
        uint256 toLp0 = amt * 1e18 / ((((start + end) / 2) * 1e18 / out1) + 1e18);
        uint256 toLp1 = amt - toLp0;

        return (toLp0, toLp1);
    }

    function quoteAndSwap(address trgtAst, uint256 amt, uint256 slp) private returns (uint256 amt0, uint256 amt1) {
        bytes memory path = pathToLp;
        (uint256 toLp0, uint256 toLp1) = quoteAddLiquidity(amt, trgtAst, path);
        address token0 = address(hypervisor.token0());

        if (trgtAst == token0) {
            swap(trgtAst, address(hypervisor.token1()), path, toLp1, slp);
        } else {
            swap(trgtAst, token0, path, toLp0, slp);
        }

        amt0 = hypervisor.token0().balanceOf(address(this));
        amt1 = hypervisor.token1().balanceOf(address(this));
    }

    function swap(address trgtAst, address ast, bytes memory path, uint256 toLp, uint256 slp) private {
        uint256 min = strategyHelper.convert(trgtAst, ast, toLp) * (10000 - slp) / 10000;

        push(IERC20(trgtAst), address(strategyHelperUniswapV3), toLp);

        strategyHelperUniswapV3.swap(trgtAst, path, toLp, min, address(this));
    }

    function valueLiquidity() private view returns (uint256) {
        uint32 period = twapPeriod;
        uint32[] memory secondsAgos = new uint32[](2);

        secondsAgos[0] = period;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = hypervisor.pool().observe(secondsAgos);
        uint160 midX96 = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int32(period)));
        (uint256 bas0, uint256 bas1) = getPosition(midX96, hypervisor.baseLower(), hypervisor.baseUpper());
        (uint256 lim0, uint256 lim1) = getPosition(midX96, hypervisor.limitLower(), hypervisor.limitUpper());
        uint256 val0 = strategyHelper.value(address(hypervisor.token0()), bas0 + lim0 + hypervisor.token0().balanceOf(address(hypervisor)));
        uint256 val1 = strategyHelper.value(address(hypervisor.token1()), bas1 + lim1 + hypervisor.token1().balanceOf(address(hypervisor)));
        uint256 bal = hypervisor.balanceOf(address(this));
        uint256 spl = hypervisor.totalSupply();

        val0 = val0 * bal / spl;
        val1 = val1 * bal / spl;

        return val0 + val1;
    }

    function totalManagedAssets() private view returns (uint256) {
        return hypervisor.balanceOf(address(this));
    }

    function getPosition(uint160 midX96, int24 minTick, int24 maxTick) private view returns (uint256, uint256) {
        bytes32 posId = keccak256(abi.encodePacked(address(hypervisor), minTick, maxTick));
        (uint128 liq,,, uint128 owed0, uint128 owed1) = hypervisor.pool().positions(posId);
        (uint256 amt0, uint256 amt1) = LiquidityAmounts.getAmountsForLiquidity(
            midX96, TickMath.getSqrtRatioAtTick(minTick), TickMath.getSqrtRatioAtTick(maxTick), liq
        );

        return (amt0 + uint256(owed0), amt1 + uint256(owed1));
    }
}


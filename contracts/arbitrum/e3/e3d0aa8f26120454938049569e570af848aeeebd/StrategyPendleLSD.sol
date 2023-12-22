// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPSwapAggregator, IPRouter, IPMarket, ILpOracleHelper} from "./IPendle.sol";
import {IERC20} from "./IERC20.sol";
import {Strategy} from "./Strategy.sol";

contract StrategyPendleLSD is Strategy {
    IPRouter public router;
    IPMarket public market;
    ILpOracleHelper public lpOracleHelper;
    IERC20 public lsdEth;
    IERC20 public weth;
    string public name;
    address public targetAsset;
    uint32 public twapPeriod = 1800;

    error PriceSlipped();

    constructor(
        address _strategyHelper,
        address _lpOracleHelper,
        address _router,
        address _market,
        address _lsdEth,
        address _weth,
        address _targetAsset
    ) Strategy(_strategyHelper) {
        lpOracleHelper = ILpOracleHelper(_lpOracleHelper);
        router = IPRouter(_router);
        market = IPMarket(_market);
        lsdEth = IERC20(_lsdEth);
        weth = IERC20(_weth);
        targetAsset = _targetAsset;
        name = string(abi.encodePacked("Pendle ", lsdEth.symbol()));
    }

    function setTargetAsset(address newTargetAsset) external auth {
        targetAsset = newTargetAsset;
    }

    function setTwapPeriod(uint32 newTwapPeriod) external auth {
        twapPeriod = newTwapPeriod;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        pull(IERC20(ast), msg.sender, amt);

        uint256 slp = getSlippage(dat);
        uint256 tma = totalManagedAssets();
        uint256 lpAmt = deposit(ast, amt, slp);
        uint256 sha = tma == 0 ? lpAmt : (lpAmt * totalShares) / tma;

        if (valueLiquidity(lpAmt) < strategyHelper.value(ast, amt) * (10000 - slp) / 10000) revert PriceSlipped();

        return sha;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        uint256 amt = (sha * totalManagedAssets()) / totalShares;
        uint256 rate = valueLiquidity(amt);
        uint256 slp = getSlippage(dat);
        uint256 bal = withdraw(ast, amt, slp);

        if (rate < strategyHelper.value(ast, bal) * (10000 - slp) / 10000) revert PriceSlipped();

        return bal;
    }

    function _earn() internal override {
        address[] memory rewardTokens = market.getRewardTokens();
        uint256 len = rewardTokens.length;
        address trgtAst = targetAsset;
        uint256 slp = slippage;

        market.redeemRewards(address(this));

        for (uint256 i = 0; i < len; ++i) {
            uint256 bal = IERC20(rewardTokens[i]).balanceOf(address(this));

            if (strategyHelper.value(rewardTokens[i], bal) < 0.5e18) continue;

            IERC20(rewardTokens[i]).approve(address(strategyHelper), bal);

            strategyHelper.swap(rewardTokens[i], trgtAst, bal, slp, address(this));
        }

        uint256 trgtAstBal = IERC20(trgtAst).balanceOf(address(this));

        if (strategyHelper.value(trgtAst, trgtAstBal) > 0.5e18) {
            deposit(trgtAst, trgtAstBal, slp);
        }
    }

    function _exit(address str) internal override {
        push(market, str, totalManagedAssets());
    }

    // Is empty because Pendle's LPs are not staked somewhere else.
    function _move(address old) internal override {}

    function _rate(uint256 sha) internal view override returns (uint256) {
        return sha * valueLiquidity(totalManagedAssets()) / totalShares;
    }

    function deposit(address ast, uint256 amt, uint256 slp) private returns (uint256) {
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 bal = strategyHelper.swap(ast, address(lsdEth), amt, slp, address(this));
        return addPendleLiquidity(bal);
    }

    function withdraw(address ast, uint256 amt, uint256 slp) private returns (uint256) {
        uint256 bal = removePendleLiquidity(amt);
        lsdEth.approve(address(strategyHelper), bal);
        return strategyHelper.swap(address(lsdEth), ast, bal, slp, msg.sender);
    }

    function addPendleLiquidity(uint256 amt) private returns (uint256 netLpOut) {
        address ast = address(lsdEth);
        IPMarket.ApproxParams memory approxParams = IPMarket.ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0,
            maxIteration: 256,
            eps: 1e14 // Maximum 0.01% unused
        });
        IPSwapAggregator.SwapData memory swapData = IPSwapAggregator.SwapData({
            swapType: IPSwapAggregator.SwapType.NONE,
            extRouter: address(0),
            extCalldata: "",
            needScale: false
        });
        IPRouter.TokenInput memory input = IPRouter.TokenInput({
            tokenIn: ast,
            netTokenIn: amt,
            tokenMintSy: ast,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: swapData
        });

        IERC20(ast).approve(address(router), amt);

        (netLpOut,) = router.addLiquiditySingleToken(address(this), address(market), 0, approxParams, input);
    }

    function removePendleLiquidity(uint256 amt) private returns (uint256 netTokenOut) {
        address ast = address(lsdEth);
        IPSwapAggregator.SwapData memory swapData = IPSwapAggregator.SwapData({
            swapType: IPSwapAggregator.SwapType.NONE,
            extRouter: address(0),
            extCalldata: "",
            needScale: false
        });
        IPRouter.TokenOutput memory output = IPRouter.TokenOutput({
            tokenOut: ast,
            minTokenOut: 0,
            tokenRedeemSy: ast,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: swapData
        });

        market.approve(address(router), amt);

        (netTokenOut,) = router.removeLiquiditySingleToken(address(this), address(market), amt, output);
    }

    function valueLiquidity(uint256 amt) private view returns (uint256) {
        address lsdEthAddress = address(lsdEth);
        uint256 lsdEthPrice = strategyHelper.price(lsdEthAddress);
        uint256 k = strategyHelper.convert(lsdEthAddress, address(weth), 1e18);
        uint256 lpRate = lpOracleHelper.getLpToAssetRate(market, twapPeriod);

        return (lsdEthPrice * lpRate / k) * amt / 1e18;
    }

    function totalManagedAssets() private view returns (uint256) {
        return market.balanceOf(address(this));
    }
}


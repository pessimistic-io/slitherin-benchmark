// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPSwapAggregator, IPRouter, IPMarket, ILpOracleHelper} from "./IPendle.sol";
import {IPairUniV2} from "./IPairUniV2.sol";
import {IERC20} from "./IERC20.sol";
import {Strategy} from "./Strategy.sol";

contract StrategyPendleCamelot is Strategy {
    IPRouter public router;
    IPMarket public market;
    IPairUniV2 public pair;
    ILpOracleHelper public lpOracleHelper;
    address public targetAsset;
    uint32 public twapPeriod = 1800;

    error PriceSlipped();

    constructor(
        address _strategyHelper,
        address _lpOracleHelper,
        address _router,
        address _market,
        address _pair,
        address _targetAsset
    ) Strategy(_strategyHelper) {
        lpOracleHelper = ILpOracleHelper(_lpOracleHelper);
        router = IPRouter(_router);
        market = IPMarket(_market);
        pair = IPairUniV2(_pair);
        targetAsset = _targetAsset;
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
        IPairUniV2 pr = pair;
        IERC20 tok0 = IERC20(pr.token0());
        IERC20 tok1 = IERC20(pr.token1());
        uint256 haf = amt / 2;

        IERC20(ast).approve(address(strategyHelper), amt);

        strategyHelper.swap(ast, address(tok0), haf, slp, address(this));
        strategyHelper.swap(ast, address(tok1), amt - haf, slp, address(this));

        push(tok0, address(pr), tok0.balanceOf(address(this)));
        push(tok1, address(pr), tok1.balanceOf(address(this)));

        pr.mint(address(this));
        pr.skim(address(this));

        return addPendleLiquidity(IERC20(address(pr)).balanceOf(address(this)));
    }

    function withdraw(address ast, uint256 amt, uint256 slp) private returns (uint256) {
        IPairUniV2 pr = pair;
        uint256 liq = removePendleLiquidity(amt);

        IERC20(address(pr)).transfer(address(pr), liq);

        pr.burn(address(this));

        IERC20 tok0 = IERC20(pr.token0());
        IERC20 tok1 = IERC20(pr.token1());
        uint256 bal0 = tok0.balanceOf(address(this));
        uint256 bal1 = tok1.balanceOf(address(this));

        tok0.approve(address(strategyHelper), bal0);
        tok1.approve(address(strategyHelper), bal1);

        uint256 bal;

        bal += strategyHelper.swap(address(tok0), ast, bal0, slp, msg.sender);
        bal += strategyHelper.swap(address(tok1), ast, bal1, slp, msg.sender);

        return bal;
    }

    function addPendleLiquidity(uint256 amt) private returns (uint256 netLpOut) {
        address pr = address(pair);
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
            tokenIn: pr,
            netTokenIn: amt,
            tokenMintSy: pr,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: swapData
        });

        IERC20(pr).approve(address(router), amt);

        (netLpOut,) = router.addLiquiditySingleToken(address(this), address(market), 0, approxParams, input);
    }

    function removePendleLiquidity(uint256 amt) private returns (uint256 netTokenOut) {
        address pr = address(pair);
        IPSwapAggregator.SwapData memory swapData = IPSwapAggregator.SwapData({
            swapType: IPSwapAggregator.SwapType.NONE,
            extRouter: address(0),
            extCalldata: "",
            needScale: false
        });
        IPRouter.TokenOutput memory output = IPRouter.TokenOutput({
            tokenOut: pr,
            minTokenOut: 0,
            tokenRedeemSy: pr,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: swapData
        });

        market.approve(address(router), amt);

        (netTokenOut,) = router.removeLiquiditySingleToken(address(this), address(market), amt, output);
    }

    function valueLiquidity(uint256 amt) private view returns (uint256) {
        (uint256 pairPrice, uint256 k) = getPairPrice();
        uint256 lpRate = lpOracleHelper.getLpToAssetRate(market, twapPeriod);

        return (pairPrice * lpRate / k) * amt / 1e18;
    }

    function getPairPrice() private view returns (uint256, uint256) {
        IPairUniV2 pr = pair;
        (uint112 r0, uint112 r1,) = pr.getReserves();

        uint256 reserve0 = uint256(r0) * 1e18 / (10 ** IERC20(pr.token0()).decimals());
        uint256 reserve1 = uint256(r1) * 1e18 / (10 ** IERC20(pr.token1()).decimals());

        uint256 price0 = strategyHelper.price(pr.token0());
        uint256 price1 = strategyHelper.price(pr.token1());

        uint256 price = 2 * ((sqrt(reserve0 * reserve1) * sqrt(price0 * price1)) / pr.totalSupply());
        uint256 k = sqrt(reserve0 * reserve1) * 1e18 / pr.totalSupply();
        return (price, k);
    }

    function totalManagedAssets() private view returns (uint256) {
        return market.balanceOf(address(this));
    }
}


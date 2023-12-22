// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";
import {IJoeLBPair, IJoeLBRouter} from "./IJoe.sol";

contract StrategyJoe is Strategy {
    string public name;
    IJoeLBRouter public immutable router;
    IJoeLBPair public immutable pair;
    IERC20 public immutable tokenX;
    IERC20 public immutable tokenY;
    uint256 public immutable binStep;
    uint256 public binAmount;
    uint256[] public bins;

    constructor(address _strategyHelper, address _router, address _pair, uint256 _binStep, uint256 _binAmount)
        Strategy(_strategyHelper)
    {
        router = IJoeLBRouter(_router);
        pair = IJoeLBPair(_pair);
        tokenX = IERC20(pair.tokenX());
        tokenY = IERC20(pair.tokenY());
        binStep = _binStep;
        binAmount = _binAmount;
        name = string(abi.encodePacked("Joe ", tokenX.symbol(), "/", tokenY.symbol()));
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        (uint256 amtX, uint256 amtY,) = _amounts();
        uint256 valX = strategyHelper.value(address(tokenX), amtX);
        uint256 valY = strategyHelper.value(address(tokenY), amtY);
        return sha * (valX + valY) / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 tma = rate(totalShares);
        uint256 haf = amt / 2;
        pull(IERC20(ast), msg.sender, amt);
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 amtX = strategyHelper.swap(ast, address(tokenX), haf, slp, address(this));
        uint256 amtY = strategyHelper.swap(ast, address(tokenY), amt-haf, slp, address(this));
        uint256 valX = strategyHelper.value(address(tokenX), amtX);
        uint256 valY = strategyHelper.value(address(tokenY), amtY);
        uint256 liq = valX + valY;
        __earn(slp, 0);
        return tma == 0 ? liq : liq * totalShares / tma;
    }

    function _burn(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        __earn(slp, amt);
        uint256 bal0 = tokenX.balanceOf(address(this));
        uint256 bal1 = tokenY.balanceOf(address(this));
        tokenX.approve(address(strategyHelper), bal0);
        tokenY.approve(address(strategyHelper), bal1);
        uint256 amt0 = strategyHelper.swap(address(tokenX), ast, bal0, slp, msg.sender);
        uint256 amt1 = strategyHelper.swap(address(tokenY), ast, bal1, slp, msg.sender);
        return amt0 + amt1;
    }

    function _earn() internal override {
        __earn(slippage, 0);
    }

    function __earn(uint256 slp, uint256 pct) internal {
        pair.collectFees(address(this), bins);
        _burnLP(slp);
        _mintLP(slp, pct);
    }

    function _exit(address str) internal override {
        _burnLP(slippage);
        push(tokenX, str, tokenX.balanceOf(address(this)));
        push(tokenY, str, tokenY.balanceOf(address(this)));
    }

    function _move(address) internal override {
        _mintLP(slippage, totalShares);
    }

    function _mintLP(uint256 slp, uint256 pct) internal {
        (,, uint256 activeId) = pair.getReservesAndId();
        uint256 amtX = tokenX.balanceOf(address(this));
        uint256 amtY = tokenY.balanceOf(address(this));
        if (pct > 0) {
            amtX -= amtX * pct / totalShares;
            amtY -= amtY * pct / totalShares;
        }
        uint256 minX = amtX * (10000 - slp) / 10000;
        uint256 minY = amtY * (10000 - slp) / 10000;
        uint256 num = binAmount;
        int256[] memory deltaIds = new int256[](num * 2);
        uint256[] memory distributionX = new uint256[](num * 2);
        uint256[] memory distributionY = new uint256[](num * 2);
        uint256 sha = 1e18 / num;
        for (uint256 i = 0; i < num; i++) {
            deltaIds[i] = int256(i+1);
            deltaIds[num+i] = 0 - int256(i+1);
            distributionX[i] = i > 0 ? sha : 1e18 - ((num-1) * sha);
            distributionY[num+i] = i > 0 ? sha : 1e18 - ((num-1) * sha);
        }
        tokenX.approve(address(router), amtX);
        tokenY.approve(address(router), amtY);
        (bins,) = router.addLiquidity(IJoeLBRouter.LiquidityParameters(
            address(tokenX), address(tokenY), binStep,
            amtX, amtY, minX, minY,
            activeId, 0, deltaIds, distributionX, distributionY,
            address(this),
            block.timestamp
        ));
    }

    function _burnLP(uint256 slp) internal {
        (uint256 amtX, uint256 amtY, uint256[] memory amounts) = _amounts();
        if (amounts.length == 0) return;
        uint256 minX = amtX * (10000 - slp) / 10000;
        uint256 minY = amtY * (10000 - slp) / 10000;
        pair.setApprovalForAll(address(router), true);
        router.removeLiquidity(
            address(tokenX), address(tokenY), uint16(binStep), minX, minY,
            bins, amounts, address(this), block.timestamp
        );
    }

    function _amounts() internal view returns (uint256, uint256, uint256[] memory) {
        uint256 num = bins.length;
        uint256[] memory amounts = new uint256[](num);
        uint256 amtX = 0;
        uint256 amtY = 0;
        for (uint256 i = 0; i < num; i++) {
            uint256 id = bins[i];
            uint256 amt = pair.balanceOf(address(this), id);
            amounts[i] = amt;
            (uint256 resX, uint256 resY) = pair.getBin(uint24(id));
            amtX += amt * resX / pair.totalSupply(id);
            amtY += amt * resY / pair.totalSupply(id);
        }
        return (amtX, amtY, amounts);
    }

    function _totalManagedAssets() internal view returns (uint256) {
        uint256 tot = 0;
        uint256 num = bins.length;
        for (uint256 i = 0; i < num; i++) {
            tot = tot +  pair.balanceOf(address(this), bins[i]);
        }
        return tot;
    }
}


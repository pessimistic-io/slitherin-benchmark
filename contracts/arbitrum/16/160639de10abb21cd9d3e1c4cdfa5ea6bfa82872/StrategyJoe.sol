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

    constructor(address _strategyHelper, address _router, address _pair, uint256 _binAmount)
        Strategy(_strategyHelper)
    {
        router = IJoeLBRouter(_router);
        pair = IJoeLBPair(_pair);
        tokenX = IERC20(pair.getTokenX());
        tokenY = IERC20(pair.getTokenY());
        binStep = uint256(pair.getBinStep());
        binAmount = _binAmount;
        name = string(abi.encodePacked("Joe ", tokenX.symbol(), "/", tokenY.symbol()));
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        (uint256 amtX, uint256 amtY,) = _amounts();
        uint256 balX = tokenX.balanceOf(address(this));
        uint256 balY = tokenY.balanceOf(address(this));
        uint256 valX = strategyHelper.value(address(tokenX), amtX+balX);
        uint256 valY = strategyHelper.value(address(tokenY), amtY+balY);
        return sha * (valX + valY) / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 slp = getSlippage(dat);
        uint256 tma = rate(totalShares);
        uint256 haf = amt / 2;
        pull(IERC20(ast), msg.sender, amt);
        IERC20(ast).approve(address(strategyHelper), amt);
        uint256 amtX = strategyHelper.swap(ast, address(tokenX), haf, slp, address(this));
        uint256 amtY = strategyHelper.swap(ast, address(tokenY), amt - haf, slp, address(this));
        uint256 valX = strategyHelper.value(address(tokenX), amtX);
        uint256 valY = strategyHelper.value(address(tokenY), amtY);
        uint256 liq = valX + valY;
        return tma == 0 ? liq : liq * totalShares / tma;
    }

    function _burn(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        uint256 tot = totalShares;
        uint256 slp = getSlippage(dat);
        _burnLP(amt * 1e18 / tot);
        uint256 shaX;
        uint256 shaY;
        {
            uint256 balX = tokenX.balanceOf(address(this));
            uint256 balY = tokenY.balanceOf(address(this));
            (uint256 valX, uint256 valY,) = _amounts();
            shaX = amt * (balX + valX) / tot;
            shaY = amt * (balY + valY) / tot;
        }
        tokenX.approve(address(strategyHelper), shaX);
        tokenY.approve(address(strategyHelper), shaY);
        uint256 amtX = strategyHelper.swap(address(tokenX), ast, shaX, slp, msg.sender);
        uint256 amtY = strategyHelper.swap(address(tokenY), ast, shaY, slp, msg.sender);
        return amtX + amtY;
    }

    function _earn() internal override {
        _burnLP(1e18);
        _rebalance(slippage);
        _mintLP(slippage);
    }

    function _exit(address str) internal override {
        _burnLP(1e18);
        push(tokenX, str, tokenX.balanceOf(address(this)));
        push(tokenY, str, tokenY.balanceOf(address(this)));
    }

    function _move(address) internal override {
        _rebalance(slippage);
        _mintLP(slippage);
    }

    function _rebalance(uint256 slp) internal {
        uint256 amtX = tokenX.balanceOf(address(this));
        uint256 amtY = tokenY.balanceOf(address(this));
        uint256 valX = strategyHelper.value(address(tokenX), amtX);
        uint256 valY = strategyHelper.value(address(tokenY), amtY);
        uint256 haf = (valX + valY) / 2;
        if (valX < valY) {
            uint256 ned = haf - valX;
            if (ned > 0.5e18) {
                uint256 amt = ned * 1e18 / strategyHelper.price(address(tokenY));
                amt = amt * (10 ** tokenY.decimals()) / 1e18;
                tokenY.approve(address(strategyHelper), amt);
                strategyHelper.swap(address(tokenY), address(tokenX), amt, slp, address(this));
            }
        } else {
            uint256 ned = haf - valY;
            if (ned > 0.5e18) {
                uint256 amt = ned * 1e18 / strategyHelper.price(address(tokenX));
                amt = amt * (10 ** tokenX.decimals()) / 1e18;
                tokenX.approve(address(strategyHelper), amt);
                strategyHelper.swap(address(tokenX), address(tokenY), amt, slp, address(this));
            }
        }
    }

    function _mintLP(uint256 slp) internal {
        uint24 activeId = pair.getActiveId();
        uint256 amtX = tokenX.balanceOf(address(this));
        uint256 amtY = tokenY.balanceOf(address(this));
        uint256 minX = amtX * (10000 - slp) / 10000;
        uint256 minY = amtY * (10000 - slp) / 10000;
        uint256 num = binAmount;
        int256[] memory deltaIds = new int256[](num * 2);
        uint256[] memory distributionX = new uint256[](num * 2);
        uint256[] memory distributionY = new uint256[](num * 2);
        uint256 sha = 1e18 / num;
        for (uint256 i = 0; i < num; i++) {
            deltaIds[i] = int256(i + 1);
            deltaIds[num + i] = 0 - int256(i + 1);
            distributionX[i] = i > 0 ? sha : 1e18 - ((num - 1) * sha);
            distributionY[num + i] = i > 0 ? sha : 1e18 - ((num - 1) * sha);
        }
        tokenX.approve(address(router), amtX);
        tokenY.approve(address(router), amtY);
        (,,,, bins,) = router.addLiquidity(
            IJoeLBRouter.LiquidityParameters(
                address(tokenX),
                address(tokenY),
                binStep,
                amtX,
                amtY,
                minX,
                minY,
                activeId,
                0,
                deltaIds,
                distributionX,
                distributionY,
                address(this),
                address(this),
                block.timestamp
            )
        );
    }

    function _burnLP(uint256 pct) internal {
        (,, uint256[] memory amounts) = _amounts();
        uint256 len = amounts.length;
        if (len == 0) return;
        for (uint256 i = 0; i < len; i++) {
            amounts[i] = amounts[i] * pct / 1e18;
        }
        pair.approveForAll(address(router), true);
        router.removeLiquidity(
            address(tokenX),
            address(tokenY),
            uint16(binStep), 0, 0, bins, amounts,
            address(this),
            block.timestamp
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
            (uint128 resX, uint128 resY) = pair.getBin(uint24(id));
            uint256 supply = pair.totalSupply(id);
            amtX += mulDiv(amt, uint256(resX), supply);
            amtY += mulDiv(amt, uint256(resY), supply);
        }
        return (amtX, amtY, amounts);
    }

    // Source: https://github.com/paulrberg/prb-math/blob/86c068e21f9ba229025a77b951bd3c4c4cf103da/contracts/PRBMath.sol#L394
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // Compute the product mod 2**256 and mod 2**256 - 1
        // then use the Chinese Remainder Theorem to reconstruct
        // the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2**256 + prod0
        uint256 prod0; // Least significant 256 bits of the product
        uint256 prod1; // Most significant 256 bits of the product
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }
        require(denominator > prod1);
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }
        unchecked {
            uint256 twos = (type(uint256).max - denominator + 1) & denominator;
            assembly {
                denominator := div(denominator, twos)
            }
            assembly {
                prod0 := div(prod0, twos)
            }
            assembly {
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;
            uint256 inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv; // inverse mod 2**8
            inv *= 2 - denominator * inv; // inverse mod 2**16
            inv *= 2 - denominator * inv; // inverse mod 2**32
            inv *= 2 - denominator * inv; // inverse mod 2**64
            inv *= 2 - denominator * inv; // inverse mod 2**128
            inv *= 2 - denominator * inv; // inverse mod 2**256
            result = prod0 * inv;
            return result;
        }
    }
}


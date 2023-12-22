// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
//import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { TickMath } from "./TickMath.sol";

import { Initializable } from "./Initializable.sol";
import { Adminable } from "./Adminable.sol";

contract BoosterOracle is Initializable, Adminable {
    address public usdLikeToken;
    address public duetToken;
    IUniswapV3Factory public uniswapV3Factory;
    uint24 public duetPoolFee;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IUniswapV3Factory uniswapV3Factory_,
        address usdLikeToken_,
        address duetToken_,
        uint24 duetPoolFee_
    ) public initializer {
        uniswapV3Factory = uniswapV3Factory_;
        usdLikeToken = usdLikeToken_;
        duetToken = duetToken_;
        duetPoolFee = duetPoolFee_;
        _setAdmin(msg.sender);
    }

    function getPrice(address token_) public view returns (uint256 price) {
        address poolAddress = uniswapV3Factory.getPool(duetToken, usdLikeToken, duetPoolFee);

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 3600 * 6;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        int24 averageTick = int24((tickCumulatives[1] - tickCumulatives[0]) / 3600);
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        price = (uint256(sqrtPriceX96) ** 2 * (10 ** 20)) / (2 ** (96 * 2));
    }
}


//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";
import {IChronosRouter} from "./IChronosRouter.sol";
import {LockingToken} from "./ILockdropPhase1.sol";

/**
 * @title ILockdropPhase1Helper
 * @notice This contracts reduces the bytecode of the LockdropPhase1 contract.
 */

interface ILockdropPhase1Helper {
    error PairAlreadyCreated();

    /**
     * @notice Function created to remove liquidity on the dex.
     * @param  token Struct of token parameters.
     * @param  min0  Minial amount of token0.
     * @param  min1 Minimal amount of token1.
     * @param  deadline Deadline to exectue.
     */
    function removeLiquidity(
        LockingToken memory token,
        uint256 min0,
        uint256 min1,
        uint256 deadline
    ) external;

    /**
     * @notice Function returnes the price of the token
     * @param token LPtoken
     * @param tokenAAddress Address of A token.
     * @param tokenAPrice Amount of wei ETH * 2**112
     * @param tokenBPrice Amount of wei ETH * 2**112
     * @return uint256 Price.
     */
    function getPrice(
        address token,
        address tokenAAddress,
        uint256 tokenAPrice,
        uint256 tokenBPrice
    ) external view returns (uint256);
}


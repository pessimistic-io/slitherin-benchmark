// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

//import '../IUniswapV2/IUniswapV2Router01.sol';
import "./IUniswapV2Router02.sol";
import "./ICamelotRouter.sol";

interface IHybridRouter is IUniswapV2Router02, ICamelotRouter {
}


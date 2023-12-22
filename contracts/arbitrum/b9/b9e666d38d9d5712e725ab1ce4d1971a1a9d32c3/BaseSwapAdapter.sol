// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @dev abstract contract meant solely to force all SwapAdapters to implement the same swap() function.
 */
abstract contract BaseSwapAdapter {
    function swap(address _outputToken, bytes calldata _swapData) external virtual returns (uint256);
}


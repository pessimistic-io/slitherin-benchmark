pragma solidity 0.8.17;

import { IHandlerContract } from "./IHandlerContract.sol";

interface ISwapManager is IHandlerContract {
    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _minOut, bytes calldata _data)
        external
        returns (uint256 _amountOut);
}


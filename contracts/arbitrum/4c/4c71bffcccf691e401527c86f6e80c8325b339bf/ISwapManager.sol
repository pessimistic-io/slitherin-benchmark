pragma solidity 0.8.17;
import {IHandlerContract} from "./IHandlerContract.sol";

interface ISwapManager is IHandlerContract {
    function swap(
        address _tokenIn,
        address _tokenOut,
        uint _amountIn,
        uint _minOut,
        bytes calldata _data
    ) external returns (uint _amountOut);
}


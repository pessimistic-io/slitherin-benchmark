pragma solidity 0.8.17;
import {BaseHandler} from "./BaseHandler.sol";
import {ISwapManager} from "./ISwapManager.sol";
import {IHandlerContract} from "./IHandlerContract.sol";
import {ERC20} from "./ERC20.sol";

/**
 * @title BaseSwapManager
 * @author Umami DAO
 * @notice Abstract base contract for implementing swap managers.
 * @dev This contract provides common functionality for swap manager implementations and enforces
 * swap checks using the `swapChecks` modifier.
 */
abstract contract BaseSwapManager is BaseHandler, ISwapManager {
    error InsufficientOutput();
    error InsufficientInput();
    error InvalidInput();

    /**
     * @notice Returns an empty array for callback signatures.
     * @return _ret An empty bytes4[] array.
     */
    function callbackSigs() external pure returns (bytes4[] memory _ret) {
        _ret = new bytes4[](0);
    }

    /**
     * @notice Modifier to enforce swap checks, ensuring sufficient input and output token amounts.
     * @param _tokenIn The address of the input token.
     * @param _tokenOut The address of the output token.
     * @param _amountIn The amount of input tokens to swap.
     * @param _minOut The minimum amount of output tokens to receive.
     */
    modifier swapChecks(
        address _tokenIn,
        address _tokenOut,
        uint _amountIn,
        uint _minOut
    ) {
        uint tokenInBalance = ERC20(_tokenIn).balanceOf(address(this));
        if (tokenInBalance < _amountIn) revert InsufficientInput();
        uint tokenOutBalanceBefore = ERC20(_tokenOut).balanceOf(address(this));
        _;
        uint tokenOutBalanceAfter = ERC20(_tokenOut).balanceOf(address(this));
        uint actualOut = tokenOutBalanceAfter - tokenOutBalanceBefore;
        if (actualOut < _minOut) revert InsufficientOutput();
    }
}


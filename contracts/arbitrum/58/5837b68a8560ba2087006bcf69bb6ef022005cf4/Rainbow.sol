// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./MiddlewareImplBase.sol";
import "./errors.sol";

/**
// @title Rainbow Swap Implementation
// @notice Called by the registry before cross chain transfers if the user requests
// for a swap
// @dev Follows the interface of Swap Impl Base
// @author Socket - reddyismav
*/
contract RainbowSwapImpl is MiddlewareImplBase {
    using SafeERC20 for IERC20;
    address payable public rainbowSwapAggregator;
    event UpdateRainbowSwapAggregatorAddress(
        address indexed rainbowSwapAggregator
    );
    event AmountRecieved(
        uint256 amount,
        address tokenAddress,
        address receiver
    );
    address private constant NATIVE_TOKEN_ADDRESS =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// rainbow swap aggregator contract is payable to allow ethereum swaps
    constructor(address registry, address _rainbowSwapAggregator)
        MiddlewareImplBase(registry)
    {
        rainbowSwapAggregator = payable(_rainbowSwapAggregator);
    }

    /// @notice Sets _rainbowSwapAggregator address
    /// @param _rainbowSwapAggregator is the address for rainbowSwapAggregator
    function setRainbowSwapAggregator(address _rainbowSwapAggregator)
        external
        onlyOwner
    {
        rainbowSwapAggregator = payable(_rainbowSwapAggregator);
        emit UpdateRainbowSwapAggregatorAddress(_rainbowSwapAggregator);
        (_rainbowSwapAggregator);
    }

    receive() external payable {}

    fallback() external payable {}

    /**
    // @notice Function responsible for swapping from one token to a different token
    // @dev This is called only when there is a request for a swap. 
    // @param from userAddress or sending address.
    // @param fromToken token to be swapped
    // @param amount amount to be swapped 
    // param to not required. This is there only to follow the MiddlewareImplBase
    // @param swapExtraData data required for rainbowSwapAggregator to get the swap done
    */
    function performAction(
        address from,
        address fromToken,
        uint256 amount,
        address receiverAddress, // receiverAddress
        bytes memory swapExtraData
    ) external payable override onlyRegistry returns (uint256) {
        require(fromToken != address(0), MovrErrors.ADDRESS_0_PROVIDED);
        (address payable toTokenAddress, bytes memory swapCallData) = abi
            .decode(swapExtraData, (address, bytes));

        uint256 _initialBalanceTokenOut;
        uint256 _finalBalanceTokenOut;

        if (toTokenAddress != NATIVE_TOKEN_ADDRESS)
            _initialBalanceTokenOut = IERC20(toTokenAddress).balanceOf(
                address(this)
            );
        else _initialBalanceTokenOut = address(this).balance;

        if (fromToken != NATIVE_TOKEN_ADDRESS) {
            IERC20(fromToken).safeTransferFrom(from, address(this), amount);
            IERC20(fromToken).safeIncreaseAllowance(
                rainbowSwapAggregator,
                amount
            );

            // solhint-disable-next-line
            (bool success, ) = rainbowSwapAggregator.call(swapCallData);
            IERC20(fromToken).safeApprove(rainbowSwapAggregator, 0);
            require(success, MovrErrors.MIDDLEWARE_ACTION_FAILED);
        } else {
            (bool success, ) = rainbowSwapAggregator.call{value: amount}(
                swapCallData
            );
            require(success, MovrErrors.MIDDLEWARE_ACTION_FAILED);
        }
        if (toTokenAddress != NATIVE_TOKEN_ADDRESS)
            _finalBalanceTokenOut = IERC20(toTokenAddress).balanceOf(
                address(this)
            );
        else _finalBalanceTokenOut = address(this).balance;

        uint256 returnAmount = _finalBalanceTokenOut - _initialBalanceTokenOut;
        if (toTokenAddress == NATIVE_TOKEN_ADDRESS)
            payable(receiverAddress).transfer(returnAmount);
        else IERC20(toTokenAddress).transfer(receiverAddress, returnAmount);
        return returnAmount;
    }

    /**
    // @notice Function responsible for swapping from one token to a different token directly
    // @dev This is called only when there is a request for a swap. 
    // @param fromToken token to be swapped
    // @param amount amount to be swapped 
    // @param swapExtraData data required for the one inch aggregator to get the swap done
    */
    function performDirectAction(
        address fromToken,
        address toToken,
        address receiver,
        uint256 amount,
        bytes memory swapExtraData
    ) external payable {
        uint256 _initialBalanceTokenOut;
        uint256 _finalBalanceTokenOut;

        if (toToken != NATIVE_TOKEN_ADDRESS)
            _initialBalanceTokenOut = IERC20(toToken).balanceOf(address(this));
        else _initialBalanceTokenOut = address(this).balance;

        if (fromToken != NATIVE_TOKEN_ADDRESS) {
            IERC20(fromToken).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
            IERC20(fromToken).safeIncreaseAllowance(rainbowSwapAggregator, amount);

            // solhint-disable-next-line
            (bool success, ) = rainbowSwapAggregator.call(swapExtraData);
            IERC20(fromToken).safeApprove(rainbowSwapAggregator, 0);
            require(success, MovrErrors.MIDDLEWARE_ACTION_FAILED);
        } else {
            (bool success, ) = rainbowSwapAggregator.call{value: amount}(
                swapExtraData
            );
            require(success, MovrErrors.MIDDLEWARE_ACTION_FAILED);
        }

        if (toToken != NATIVE_TOKEN_ADDRESS)
            _finalBalanceTokenOut = IERC20(toToken).balanceOf(address(this));
        else _finalBalanceTokenOut = address(this).balance;

        uint256 returnAmount = _finalBalanceTokenOut - _initialBalanceTokenOut;
        if (toToken == NATIVE_TOKEN_ADDRESS)
            payable(receiver).transfer(returnAmount);
        else IERC20(toToken).transfer(receiver, returnAmount);
        emit AmountRecieved(returnAmount, toToken, receiver);
    }
}


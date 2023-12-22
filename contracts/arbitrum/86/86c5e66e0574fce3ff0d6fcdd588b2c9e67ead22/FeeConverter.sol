// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {IJoePair} from "./IJoePair.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";

import {BaseComponent} from "./BaseComponent.sol";
import {IOneInchRouter} from "./IOneInchRouter.sol";
import {IFeeConverter} from "./IFeeConverter.sol";

/**
 * @title Fee Converter
 * @author Trader Joe
 * @notice This contract is used to convert the protocol fees into the redistributed token and
 * send them to the receiver.
 */
contract FeeConverter is BaseComponent, IFeeConverter {
    using SafeERC20 for IERC20;

    IOneInchRouter internal constant _ONE_INCH_ROUTER = IOneInchRouter(0x1111111254EEB25477B68fb85Ed929f73A960582);

    bytes32 internal immutable _LP_CODE_HASH;
    IERC20 internal immutable _REDISTRIBUTED_TOKEN;
    address internal immutable _RECEIVER;

    /**
     * @dev Sets the redistributed token and the receiver, as well as the code hash of the v1 pair and the fee manager.
     * @param feeManager The fee manager.
     * @param v1Pair The v1 pair.
     * @param redistributedToken The redistributed token.
     * @param receiver The receiver.
     */
    constructor(address feeManager, address v1Pair, IERC20 redistributedToken, address receiver)
        BaseComponent(feeManager)
    {
        _LP_CODE_HASH = v1Pair.codehash;

        _REDISTRIBUTED_TOKEN = redistributedToken;
        _RECEIVER = receiver;
    }

    /**
     * @notice Returns the address of the 1inch router.
     * @return The address of the 1inch router.
     */
    function getOneInchRouter() external pure override returns (IOneInchRouter) {
        return _ONE_INCH_ROUTER;
    }

    /**
     * @notice Returns the address of the redistributed token.
     * @return The address of the redistributed token.
     */
    function getRedistributedToken() external view override returns (IERC20) {
        return _REDISTRIBUTED_TOKEN;
    }

    /**
     * @notice Returns the address of the receiver.
     * @return The address of the receiver.
     */
    function getReceiver() external view override returns (address) {
        return _RECEIVER;
    }

    /**
     * @notice Swaps the given token for another one using the 1inch router.
     * @param executor The address that will execute the swap.
     * @param desc The description of the swap.
     * @param data The data of the swap.
     */
    function convert(address executor, IOneInchRouter.SwapDescription calldata desc, bytes calldata data)
        external
        override
        onlyDelegateCall
    {
        _swap(executor, desc, data);
    }

    /**
     * @notice Batch swaps the given tokens for another ones using the 1inch router.
     * @param executor The address that will execute the swaps.
     * @param descs The descriptions of the swaps.
     * @param data The data of the swaps.
     */
    function batchConvert(address executor, IOneInchRouter.SwapDescription[] calldata descs, bytes[] calldata data)
        external
        override
        onlyDelegateCall
    {
        if (descs.length != data.length) revert FeeConverter__InvalidLength();

        for (uint256 i; i < descs.length;) {
            _swap(executor, descs[i], data[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Unwraps the given lp token from the fee manager and send the underlying tokens back to it.
     * @dev The lpToken must be a V1 pair.
     * @param lpToken The lpToken to unwrap.
     */
    function unwrapLpToken(address lpToken) external override onlyDelegateCall {
        _unwrapLpToken(lpToken);
    }

    /**
     * @notice Batch unwraps the given lp tokens from the fee manager and send the underlying tokens back to it.
     * @dev The lpTokens must be V1 pairs.
     * @param lpTokens The list of lpTokens to unwrap.
     */
    function batchUnwrapLpToken(address[] calldata lpTokens) external override onlyDelegateCall {
        for (uint256 i; i < lpTokens.length;) {
            _unwrapLpToken(lpTokens[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Approves the 1inch router to spend the given token and swaps it for another one.
     * @param executor The address that will execute the swap.
     * @param desc The description of the swap.
     * @param data The data of the swap.
     */
    function _swap(address executor, IOneInchRouter.SwapDescription calldata desc, bytes calldata data) private {
        if (desc.dstToken != _REDISTRIBUTED_TOKEN) revert FeeConverter__InvalidDstToken();
        if (desc.dstReceiver != _RECEIVER) revert FeeConverter__InvalidReceiver();
        if (desc.amount == 0 || desc.minReturnAmount == 0) revert FeeConverter__ZeroAmount();

        if (desc.srcToken == _REDISTRIBUTED_TOKEN) return _tranferRedistributedToken(desc.amount);

        uint256 allowance = desc.srcToken.allowance(address(this), address(_ONE_INCH_ROUTER));
        if (allowance < desc.amount) {
            if (allowance > 0) desc.srcToken.approve(address(_ONE_INCH_ROUTER), 0);
            desc.srcToken.approve(address(_ONE_INCH_ROUTER), type(uint256).max);
        }

        (uint256 amountOut, uint256 amountIn) = _ONE_INCH_ROUTER.swap(executor, desc, "", data);

        emit Swap(_RECEIVER, address(desc.srcToken), address(desc.dstToken), amountIn, amountOut);
    }

    /**
     * @dev Unwraps the given lp token from the fee manager and send the underlying tokens to it.
     * The lpToken must be a V1 pair.
     * @param lpToken The lpToken to unwrap.
     */
    function _unwrapLpToken(address lpToken) private {
        if (lpToken.codehash != _LP_CODE_HASH) revert FeeConverter__HashMismatch(lpToken);

        uint256 balance = IERC20(lpToken).balanceOf(address(this));
        if (balance == 0) revert FeeConverter__InsufficientBalance(lpToken);

        IERC20(lpToken).safeTransfer(address(lpToken), balance);
        IJoePair(lpToken).burn(address(this));
    }

    /**
     * @dev Transfers the redistributed token to the receiver.
     * @param amount The amount to transfer.
     */
    function _tranferRedistributedToken(uint256 amount) private {
        _REDISTRIBUTED_TOKEN.safeTransfer(_RECEIVER, amount);

        emit Swap(_RECEIVER, address(_REDISTRIBUTED_TOKEN), address(_REDISTRIBUTED_TOKEN), amount, amount);
    }
}


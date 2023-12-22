// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import { SafeTransferLib } from "./SafeTransferLib.sol";
import "./IERC4626.sol";
import "./UniV3Wrapper.sol";
import "./console.sol";

contract TokenSwapper {
    using SafeTransferLib for ERC20;

    error ErrSwapFailed();
    error ErrTokenNotSupported(ERC20);

    address public immutable zeroXExchangeProxy;

    constructor(
        address _zeroXExchangeProxy
    ) {
        zeroXExchangeProxy = _zeroXExchangeProxy;
    }

    function swap(address inputToken, bytes calldata extraData)
        external returns (uint256 extraAmount, uint256 amountReturned) {

        (address toToken,
         address recipient,
         uint256 amountToMin,
         bytes memory swapData) = abi.decode(extraData, (address, address, uint256, bytes));

        return this.swap(ERC20(inputToken), ERC20(toToken), recipient, amountToMin, swapData);
    }

    function swap(
        ERC20 collateral,
        ERC20 toToken,
        address recipient,
        uint256 amountToMin,
        bytes calldata swapData
    ) public returns (uint256 extraAmount, uint256 amountReturned) {
        collateral.approve(address(zeroXExchangeProxy), type(uint256).max);
        (bool success, ) = zeroXExchangeProxy.call(swapData);
        if (!success) {
            revert ErrSwapFailed();
        }
        
        amountReturned = toToken.balanceOf(address(this));
        extraAmount = amountReturned - amountToMin;

        toToken.safeTransfer(recipient, amountReturned);
    }
}


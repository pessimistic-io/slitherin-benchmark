// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import { SafeTransferLib } from "./SafeTransferLib.sol";
import "./IERC4626.sol";
import "./UniV3Wrapper.sol";
import "./console.sol";

contract LevWrapperSwapper {
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

        (address vault,
         address recipient,
         uint256 amountToMin) = abi.decode(extraData, (address, address, uint256));

        return this.swap(UniV3Wrapper(vault), recipient, amountToMin);
    }

    function swap(
        UniV3Wrapper vault,
        address recipient,
        uint256 amountToMin
    ) public returns (uint256 extraAmount, uint256 amountReturned) {
        {
            uint256 balance0 = vault.token0().balanceOf(address(this));
            uint256 balance1 = vault.token1().balanceOf(address(this));

            (uint256 swapAmount, bool zeroForOne) = vault.mintMaxLiquidityPreview(balance0, balance1);

            if (zeroForOne) {
                vault.token0().approve(address(vault), type(uint256).max);
                balance1 = 0;
            } else {
                vault.token1().approve(address(vault), type(uint256).max);
                balance0 = 0;
            }

            (, , amountReturned) = vault.zapIn(balance0, balance1, swapAmount, zeroForOne, 0);
        }
        
        extraAmount = amountReturned - amountToMin;

        ERC20(address(vault)).safeTransfer(recipient, amountReturned);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { LibAsset } from "./LibAsset.sol";
import { LibUtil } from "./LibUtil.sol";
import { InvalidContract, NoSwapFromZeroBalance, InsufficientBalance } from "./GenericErrors.sol";
import { IERC20 } from "./IERC20.sol";
import { IAdapter } from "./IAdapter.sol";
import { LibSwap } from "./LibSwap.sol";

library LibQuote {
    function quote(uint256 _fromAmount, LibSwap.SwapData calldata _swap, address _weth) internal returns (uint256 receievedAmount) {
        if (_fromAmount == 0) revert NoSwapFromZeroBalance();

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory res) = _swap.adapter.delegatecall(
            abi.encodeWithSelector(
                IAdapter.quote.selector,
                LibAsset.isNativeAsset(_swap.fromToken) ? _weth : _swap.fromToken,
                address(0),
                _fromAmount,
                _swap.route
            )
        );
        if (!success) {
            string memory reason = LibUtil.getRevertMsg(res);
            revert(reason);
        }
        (receievedAmount) = abi.decode(res,(uint256));
        return receievedAmount;
    }
}


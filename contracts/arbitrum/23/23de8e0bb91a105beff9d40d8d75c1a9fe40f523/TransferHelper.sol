// SPDX-License-Identifier: MIT
// Taken from https://github.com/Uniswap/uniswap-lib/blob/master/src/libraries/TransferHelper.sol
pragma solidity ^0.8.19;

import { ERC20 } from "./ERC20.sol";
import { RevertMsgExtractor } from "./RevertMsgExtractor.sol";

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
// USDT is a well known token that returns nothing for its transfer, transferFrom, and approve functions
// and part of the reason this library exists
library TransferHelper {
    /// @notice Transfers assets from msg.sender to a recipient
    /// @dev Errors with the underlying revert message if transfer fails
    /// @param asset The contract address of the asset which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(address asset, address to, uint256 value) internal {
        (bool success, bytes memory data) =
        // solhint-disable-next-line avoid-low-level-calls
         address(asset).call(abi.encodeWithSelector(ERC20.transfer.selector, to, value));
        if (!(success && (data.length == 0 || abi.decode(data, (bool))))) revert(RevertMsgExtractor.getRevertMsg(data));
    }
}


//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./IERC20.sol";

/// Invalid Parameters. 
error BadUserInput();

/// @title Bulk Transfer for ERC20
/// @author Wayne (Ellerian Prince)
contract ERC20BulkTransfer {

    /// @notice Bulk transfers tokens to recipients.
    /// @param recipients Address to receive Tokens.
    /// @param amounts Amount of tokens.
    /// @return True if success.
    function bulkTransfer(address erc20Address, address[] memory recipients, uint256[] memory amounts) external returns (bool) {
        if (recipients.length != amounts.length) {
            revert BadUserInput();
        }

        IERC20 erc20Abi = IERC20(erc20Address);

        for (uint256 i = 0; i < recipients.length; i += 1) {
            erc20Abi.transferFrom(msg.sender, recipients[i], amounts[i]);
        }

        return true;
    }
}

    

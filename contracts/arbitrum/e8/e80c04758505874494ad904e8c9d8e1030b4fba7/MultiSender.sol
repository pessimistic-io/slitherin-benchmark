// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./console.sol";

import "./IERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./SafeMath.sol";

contract MultiSender is Ownable, Pausable {
    constructor() {}

    /**
     * @dev Transfer token amount for multi recipients
     * @param token token address
     * @param recipients list of recipients
     * @param amounts list of amounts corresponding for recipients
     */
    function batchTransfer(address token, address[] memory recipients, uint256[] memory amounts) public whenNotPaused {
        require(recipients.length == amounts.length, 'mismatch length of recipients and amounts');
        for (uint256 i = 0; i < recipients.length; i++) {
            IERC20(token).transferFrom(msg.sender, recipients[i], amounts[i]);
        }
    }

    /**
     * @dev Transfer token for multi recipients support multi tokens as input
     * @param tokens list of sending tokens
     * @param recipients list of recipients corresponding for tokens list
     * @param amounts list of amounts corresponding for recipients list
     */
    function batchTransferMultiTokens(
        address[] memory tokens,
        address[] memory recipients,
        uint256[] memory amounts
    ) public whenNotPaused {
        require(tokens.length == recipients.length, 'mismatch length of tokens and recipients');
        require(recipients.length == amounts.length, 'mismatch length of recipients and amounts');

        for (uint256 i = 0; i < recipients.length; i++) {
            IERC20(tokens[i]).transferFrom(msg.sender, recipients[i], amounts[i]);
        }
    }

    /**
     * @dev use to pause contract in emergency
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev using to unpause the contract
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev For emergency withdraw token sent in wrong way
     * @param token token address
     */
    function emergencyWithdraw(address token) public onlyOwner {
        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}


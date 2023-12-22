// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";

// ========================================================================
// The purpose of this contract is to separate Admin functionality from
// required Flashstake Strategy functionality.
//
// This will introduce the following Admin functionality:
// 1. Ability to withdraw any ERC20 token that is not the principal
//    token. This is to ensure users can be refunded if ERC20 tokens
//    are accidentally sent to this address.
//
// 2. Ability to set the maximum staking duration
//    (only impacts new stakes)
//
// 3. Ability to permanently lock the maximum staking duration
//    (only impacts new stakes)
// ========================================================================

abstract contract FlashStrategyAdmin is Ownable {
    using SafeERC20 for IERC20Metadata;

    address private immutable principalTokenAddress;
    address private constant glpTokenAddress = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;

    uint256 maxStakeDuration = 14515200;
    bool public maxStakeDurationLocked = false;

    constructor(address _principalTokenAddress) {
        principalTokenAddress = _principalTokenAddress;
    }

    // @notice withdraw any ERC20 token in this strategy that is not the principal or share token
    // @dev this can only be called by the strategy owner
    function withdrawERC20(address[] calldata _tokenAddresses, uint256[] calldata _tokenAmounts) external onlyOwner {
        require(_tokenAddresses.length == _tokenAmounts.length, "ARRAY SIZE MISMATCH");

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            // Ensure the token being withdrawn is not the principal token
            require(_tokenAddresses[i] != principalTokenAddress &&
                _tokenAddresses[i] != glpTokenAddress, "TOKEN ADDRESS PROHIBITED");

            // Transfer the token to the caller
            IERC20Metadata(_tokenAddresses[i]).safeTransfer(msg.sender, _tokenAmounts[i]);
        }
    }

    // @notice retrieve the maximum stake duration in seconds
    // @dev this is usually called by the Flashstake Protocol
    function getMaxStakeDuration() public view returns (uint256) {
        return maxStakeDuration;
    }

    // @notice sets the new maximum stake duration
    // @dev this can only be called by the strategy owner
    function setMaxStakeDuration(uint256 _newMaxStakeDuration) external onlyOwner {
        require(maxStakeDurationLocked == false);
        maxStakeDuration = _newMaxStakeDuration;
    }

    // @notice permanently locks the max stake duration
    // @dev this can only be called by the strategy owner
    function lockMaxStakeDuration() external onlyOwner {
        maxStakeDurationLocked = true;
    }
}


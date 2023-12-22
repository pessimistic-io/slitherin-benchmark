// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./IAirdrop.sol";
import "./IIqStaking.sol";
import "./SafeERC20.sol";
import "./extensions_IERC20Metadata.sol";

/// @title Airdrop
/// @author gotbit
contract Airdrop is IAirdrop {
    using SafeERC20 for IERC20Metadata;

    address public manager;

    constructor(address manager_) {
        require(manager_ != address(0), 'zero address');
        manager = manager_;
    }

    function setManager(address manager_) external {
        require(msg.sender == manager, 'not manager');
        require(manager_ != address(0), 'zero address');
        manager = manager_;
    }

    function airdrop(
        address token,
        uint256 amount,
        IIqStaking.UserSharesOutput[] memory receivers
    ) external {
        require(msg.sender == manager, 'not manager');
        require(receivers.length > 0, 'empty airdrop receivers');

        for (uint256 i; i < receivers.length; ) {
            uint256 userAmount = (amount * receivers[i].share) / 1 ether;
            IERC20Metadata(token).safeTransfer(receivers[i].user, userAmount);

            unchecked {
                ++i;
            }
        }
    }
}


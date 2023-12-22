// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Ownable.sol";
import "./ERC721Holder.sol";
import "./SafeERC20.sol";

import "./ILockHolder.sol";
import "./IVotingEscrow.sol";

contract LockHolder is ILockHolder, Ownable, ERC721Holder {
    using SafeERC20 for IERC20;

    IVotingEscrow public votingEscrow;
    address public partner;

    /// @param partner_ Partner address.
    /// @param votingEscrow_ VotingEscrow contract address.
    constructor(address partner_, IVotingEscrow votingEscrow_) {
        partner = partner_;
        votingEscrow = votingEscrow_;
        votingEscrow_.setApprovalForAll(msg.sender, true);
    }

    /// @inheritdoc ILockHolder
    function sendRewards(address[][] calldata tokens_) external onlyOwner {
        address m_partner = partner;
        for (uint256 i = 0; i < tokens_.length; ) {
            for (uint256 j = 0; j < tokens_[i].length; ) {
                IERC20 token = IERC20(tokens_[i][j]);
                token.safeTransfer(m_partner, token.balanceOf(address(this)));
                unchecked {
                    j++;
                }
            }
            unchecked {
                i++;
            }
        }
    }
}

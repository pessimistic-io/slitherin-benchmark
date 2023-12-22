// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IRebateHandler {
    /// @notice Emitted when the merkle root is updated.
    event MerkleRootUpdated(bytes32 merkleRoot, uint256 maxAmountToClaim);
    /// @notice Emitted when reward is paid to a user.
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice Admin updates the merkleRoot and maximum amount to claim for a particular period.
    /// @param _merkleRoot The merkleRoot of the reward distribution.
    /// @param _maxAmountToClaim Total amount of tokens that can be claimed during an epoch.
    function updateMerkleRoot(
        bytes32 _merkleRoot,
        uint256 _maxAmountToClaim
    ) external;

    /// @notice Users can claim the rewards allocated to them.
    /// @param proof The merkle proof for msg.senders distribution.
    /// @param amount The amount that can be claimed by msg.sender.
    function claimReward(bytes32[] memory proof, uint256 amount) external;

    /// @notice Allows admin to reclaim unused rewards after a period of inactivity.
    /// @param account The address of the account to which the unused tokens need to be transferred.
    function reclaimUnusedReward(address account) external;
}


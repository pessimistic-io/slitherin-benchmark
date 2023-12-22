//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./ISignature.sol";

/// Claim isn't valid.
error ClaimNotOngoing();

/// Insufficient privileges. 
error Forbidden();

// Maximum for the pool has been claimed.
error MaxClaimed();

/// Already Claimed.
error AlreadyClaimed();

/// Invalid Parameters. 
/// @param param The parameter that was invalid.
error BadUserInput(string param);

/// Invalid Address. 
/// @param addr invalid address.
error InvalidAddress(address addr);

/// Value too large. Maximum `maximum` but `attempt` provided.
/// @param attempt balance available.
/// @param maximum maximum value.
error ValueOverflow(uint256 attempt, uint256 maximum);

/// @title Claim Portal for Tales of Elleria.
/// @author Wayne (Ellerian Prince)
/// @notice Uses merkle proofs to set up reward pools for ERC20 tokens for players to claim.
/// * 1. Anyone to deposit the token ERC20 into the contract.
/// * 2. Owner calls SetupReward with the relevant parameters (amount in WEI)
/// * 3. Users can claim through contract or UI in https://app.talesofelleria.com/
/// @dev There is no direct withdraw function if required, set up a new pool and claim from it instead.
contract RewardClaim is ReentrancyGuard, Ownable {
    /// @notice The struct represents a reward pool.
    struct RewardPool {
        /// @dev Merkle root of this pool.
        bytes32 root;
        /// @dev Whether this pool is valid for claims.
        bool isValid;
        /// @dev Address of the reward ERC20 token.
        address rewardAddress;
        /// @dev Amount of tokens claimed.
        uint256 claimedAmount;
        /// @dev Maximum amount of claimable tokens.
        uint256 maxPoolAmount;
        /// @dev Mapping if an address has claimed.
        mapping (address => bool) isClaimed;
    }

    /// @dev Mapping from ID to its RewardPool.
    mapping(uint => RewardPool) private rewards;

    /// @dev Reference to the contract that does signature verifications.
    ISignature private signatureAbi;

    /// @notice Address used to verify signatures.
    address public signerAddr;

    /// @dev Initialize signature and signer.
    constructor(address signatureAddress, address signerAddress) {
        signatureAbi = ISignature(signatureAddress);
        signerAddr = signerAddress;
    }

    /// @notice Returns RewardPool for the specified rewardId.
    /// @param rewardId ID of the reward pool.
    /// @return rewardEntry RewardPool per rewardId specified.
    function getRewardPool(uint rewardId) external view returns (
        uint256, address, bool, uint256
    ) {
        return (
            rewards[rewardId].maxPoolAmount,
            rewards[rewardId].rewardAddress,
            rewards[rewardId].isValid,
            rewards[rewardId].claimedAmount
        );
    }

    /// @dev Verify that the wallet address (leaf) is part of the recipients.
    /// @param rewardId ID of the reward pool.
    /// @param leaf Encoded recipient.
    /// @param proof Merkle proof for the reward pool.
    function verify(uint rewardId, bytes32 leaf, bytes32[] memory proof) internal view returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i += 1) {
        bytes32 proofElement = proof[i];

        if (computedHash <= proofElement) {
            computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
        } else {
            computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
        }
        }

        return computedHash == rewards[rewardId].root;
    }

    /// @notice Call to claim rewards. Rewards can only be claimed once.
    /// @dev Uses merkle proof to verify eligibility + signing to verify amount.
    /// @param rewardId ID of the reward pool.
    /// @param amount Amount of tokens to receive.
    /// @param signature Signed signature to authenticate the claim.
    /// @param proof Merkle proof for the reward pool.
    function claimReward(
        uint rewardId,
        uint256 amount,
        bytes memory signature,
        bytes32[] memory proof
    ) external nonReentrant {
        if(!rewards[rewardId].isValid) {
            revert ClaimNotOngoing();
        }

        if (rewards[rewardId].isClaimed[msg.sender]) {
            revert AlreadyClaimed();
        }

        if (rewards[rewardId].claimedAmount + amount > rewards[rewardId].maxPoolAmount) {
            revert MaxClaimed();
        }

        if (
            !verify(rewardId, keccak256(abi.encode(msg.sender)), proof) || 
            !signatureAbi.verify(signerAddr, msg.sender, rewardId, "reward claim", amount, signature)
        ) {
          revert Forbidden();
        }

        rewards[rewardId].isClaimed[msg.sender] = true;
        rewards[rewardId].claimedAmount += amount;

        IERC20(rewards[rewardId].rewardAddress).transfer(msg.sender, amount);

        emit RewardClaimed(rewardId, msg.sender, rewards[rewardId].rewardAddress, amount);
    }

    /// @notice Called by owner to initialize or update a pool.
    /// @param rewardId ID of the reward pool.
    /// @param root Merkle root of the pool.
    /// @param maxPoolAmount Total reward amount available.
    /// @param rewardAddress ERC20 address for this reward.
    function initRewardPool(
        uint rewardId,
        bytes32 root,
        uint256 maxPoolAmount,
        address rewardAddress
    ) external onlyOwner {
        rewards[rewardId].root = root;
        rewards[rewardId].maxPoolAmount = maxPoolAmount;
        rewards[rewardId].rewardAddress = rewardAddress;
        rewards[rewardId].isValid = true;
    }

    /// @notice Called by owner to disable a pool.
    /// @param rewardId ID of the reward pool.
    function disableReward(uint rewardId) external onlyOwner {
        rewards[rewardId].isValid = false;
    }

    /// @notice Event emitted when a reward is claimed.
    /// @param rewardId Reward pool the reward was claimed from.
    /// @param claimedBy Address that claimed the reward.
    /// @param erc20Address Address of the reward token.
    /// @param amountClaimed Amount claimed.
    event RewardClaimed(uint indexed rewardId, address indexed claimedBy, address erc20Address, uint256 amountClaimed);
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

import "./ISignature.sol";

/// Claim isn't valid.
error ClaimNotOngoing();

/// Insufficient privileges. 
error Forbidden();

/// Already Claimed.
error AlreadyClaimed();

// Invalid Merkle Proof
error InvalidProof();

/// @title Claim Portal for Tales of Elleria.
/// @author Wayne (Ellerian Prince)
/// @notice Uses merkle proofs to set up reward pools for ERC20 tokens for players to claim.
/// * 1. Anyone to deposit the token ERC20 into the contract.
/// * 2. Owner calls SetupReward with the relevant parameters (amount in WEI)
/// * 3. Users can claim through contract or UI in https://app.talesofelleria.com/
contract RewardClaim is ReentrancyGuard, Ownable {
    /// @notice The struct represents a reward pool.
    struct RewardPool {
        /// @dev Merkle root of this pool.
        bytes32 root;
        /// @dev Whether this pool is valid for claims.
        bool isValid;
        /// @dev Address of the reward ERC20 token.
        address rewardErc20Address;
        /// @dev Mapping if an address has claimed.
        mapping (address => bool) isClaimed;
    }

    /// @dev Mapping from ID to its RewardPool.
    mapping(uint256 => RewardPool) private rewards;

    /// @dev Reference to the contract that does signature verifications.
    ISignature private signatureAbi;

    /// @notice Address used to verify signatures.
    address public signerAddr;

    /// @dev Default value of bytes32 for root comparison.
    bytes32 private defaultBytes32;

    /// @dev Initialize signature and signer.
    constructor(address signatureAddress, address signerAddress) {
        signatureAbi = ISignature(signatureAddress);
        signerAddr = signerAddress;
    }

    /// @dev Verify that the wallet address (leaf) is part of the recipients.
    /// @param rewardId ID of the reward pool.
    /// @param proof Merkle proof for the reward pool.
    /// @param amount Amount to claim.
    function verify(uint256 rewardId, bytes32[] memory proof, uint256 amount) internal view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));
        
        if (!MerkleProof.verify(proof, rewards[rewardId].root, leaf)) {
            revert InvalidProof();
        }

        return true;
    }

    /// @notice Check if a user has claimed his reward for the specified pool.
    /// @param rewardIds IDs of the reward pool.
    /// @param walletAddress User wallet address.
    function isClaimed(uint256[] memory rewardIds, address walletAddress) external view returns (bool[] memory) {
        bool[] memory claims = new bool[](rewardIds.length);

        for (uint256 i = 0; i < rewardIds.length; i += 1) {
            claims[i] = rewards[rewardIds[i]].isClaimed[walletAddress];
        }

        return claims;
    }

    /// @notice Call to claim rewards. Rewards can only be claimed once.
    /// @dev Uses merkle proof to verify eligibility and reward amount.
    /// @param rewardIds IDs of the reward pool to claim from.
    /// @param signature Signed signature to authenticate the claim.
    /// @param proof Merkle proof for the reward pool.
    /// @param amount Amount to claim.
    function claimReward(
        uint256[] memory rewardIds,
        bytes memory signature,
        bytes32[] memory proof,
        uint256 amount
    ) external nonReentrant {
        // Perform all eligibility checks and mark as claimed.
        for (uint256 i = 0; i < rewardIds.length; i += 1) {
            uint256 rewardId = rewardIds[i];

            if(!rewards[rewardId].isValid) {
                revert ClaimNotOngoing();
            }

            if (rewards[rewardId].isClaimed[msg.sender]) {
                revert AlreadyClaimed();
            }

            if (
                !verify(rewardId, proof, amount) || 
                !signatureAbi.verify(
                    signerAddr,
                    msg.sender,
                    rewardId,
                    "reward claim",
                    amount,
                    signature
                )
            ) {
                revert Forbidden();
            }

            // Mark as claimed
            rewards[rewardId].isClaimed[msg.sender] = true;
        }
      
        // Transfer reward tokens.
        for (uint256 i = 0; i < rewardIds.length; i += 1) {
            uint256 rewardId = rewardIds[i];

            IERC20(rewards[rewardId].rewardErc20Address).transfer(msg.sender, amount);
            emit RewardClaimed(
                rewardId,
                msg.sender,
                rewards[rewardId].rewardErc20Address,
                amount
            );
        }
    }

    /// @notice Called by owner to initialize or update a pool.
    /// @dev Tokens need to be transferred in separately after verification.
    /// @param rewardId ID of the reward pool.
    /// @param root Merkle root of the pool.
    /// @param rewardErc20Address ERC20 address for this reward.
    function initRewardPool(
        uint256 rewardId,
        bytes32 root,
        address rewardErc20Address
    ) external onlyOwner {
        // Cannot initialize over an existing pool
        if (rewards[rewardId].root != defaultBytes32) {
            revert Forbidden();
        }

        rewards[rewardId].root = root;
        rewards[rewardId].rewardErc20Address = rewardErc20Address;
        rewards[rewardId].isValid = true;

        emit PoolInitialized(rewardId, rewardErc20Address);
        emit PoolStatusChange(rewardId, true);
    }

    /// @notice Called by owner to disable a pool.
    /// @param rewardId ID of the reward pool.
    function updateRewardStatus(uint256 rewardId, bool isValid) external onlyOwner {
        rewards[rewardId].isValid = false;
        emit PoolStatusChange(rewardId, isValid);
    }

    /// @notice Allows the owner to withdraw ERC20 tokens from this contract.
    /// @param erc20Addr ERC20 Address to withdraw
    /// @param recipient Wallet to withdraw to
    function withdrawERC20(address erc20Addr, address recipient) external onlyOwner {
        IERC20(erc20Addr).transfer(recipient, IERC20(erc20Addr).balanceOf(address(this)));
    }

    /// @notice Event emitted when a reward pool is initialized.
    /// @param rewardId Reward pool the reward was claimed from.
    /// @param erc20Address Address of the reward token.
    event PoolInitialized(
        uint256 indexed rewardId,
        address erc20Address
    );

    /// @notice Event emitted when a reward pool is disabled/enabled.
    /// @param rewardId Reward Pool Id.
    /// @param isValid Is claiming valid.
    event PoolStatusChange(
        uint256 indexed rewardId,
        bool isValid
    );

    /// @notice Event emitted when a reward is claimed.
    /// @param rewardId Reward pool the reward was claimed from.
    /// @param claimedBy Address that claimed the reward.
    /// @param erc20Address Address of the reward token.
    /// @param amountClaimed Amount claimed.
    event RewardClaimed(
        uint256 indexed rewardId,
        address indexed claimedBy,
        address erc20Address,
        uint256 amountClaimed
    );
}

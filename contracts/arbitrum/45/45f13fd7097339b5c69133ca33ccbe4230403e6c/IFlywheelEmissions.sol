// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IFlywheelEmissions {
    struct HarvesterEmission {
        uint256 amount;
        uint256 harvesterMagic;
        uint256 additionalFlywheelMagic;
    }

    struct ContractAddresses {
        address magic;
        address gFly;
        address gFlyStaking;
        address atlasStaker;
        address treasuryVault;
        address opex;
        address vault1;
        address vault2;
        address cheese;
        address digi;
        address battleflyBot;
        address dao;
    }

    function setGFlyGameAddress(address vault, address gFlyGameAddress) external;

    function setGFlyMagicSwap(address gFlyMagicSwap) external;

    function topupHarvesterEmissions(uint256 amount, uint256 harvesterMagic, uint256 additionalFlywheelMagic) external;

    function topupFlywheelEmissions(uint256 amount) external;

    function setVaultHarvesterStake(uint256 _amount, address _vault) external;

    function claim(
        uint256 index,
        uint256 epoch,
        uint256 cumulativeFlywheelAmount,
        uint256 cumulativeHarvesterAmount,
        uint256 flywheelClaimableAtEpoch,
        uint256 harvesterClaimableAtEpoch,
        uint256 individualMiningPower,
        uint256 totalMiningPower,
        bytes32[] calldata merkleProof
    ) external;

    function setMerkleRoot(bytes32 root) external;

    function getClaimableFor(
        address account,
        uint256 cumulativeFlywheelAmount,
        uint256 cumulativeHarvesterAmount
    ) external view returns (uint256 claimable);

    function getClaimedFor(address account) external view returns (uint256);

    function getApyInBPS(
        uint256 flywheelClaimableAtEpoch,
        uint256 harvesterClaimableAtEpoch,
        uint256 totalStaked
    ) external pure returns (uint256 apyInBPS);

    function getActivatedRewardsInBPS() external view returns (uint256 rewardsActivated);

    // ========== Events ==========
    event GFlyGameAddressSet(address indexed vault, address indexed gFlyGameAddress);
    event HarvesterEmissionsToppedUp(
        uint256 amount,
        uint256 harvesterMagic,
        uint256 additionalFlywheelMagic,
        uint256 v1VaultHarvesterStake,
        uint256 v2vaultHarvesterStake,
        uint256 cheeseHarvesterStake,
        uint256 digiHarvesterStake,
        uint64 indexed epoch,
        uint256 activatedRewardsInBPS
    );
    event FlywheelEmissionsToppedUp(uint64 indexed epoch, uint256 amount);
    event Claimed(address indexed account, uint256 claimable, uint256 indexed epoch);
    event MerkleRootSet(bytes32 root, uint256 indexed emissionsEpoch);
}


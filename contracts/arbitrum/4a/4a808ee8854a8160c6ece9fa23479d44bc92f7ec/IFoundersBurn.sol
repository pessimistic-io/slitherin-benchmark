// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IFoundersBurn {
    struct BurnPosition {
        address owner;
        uint256 amountPerEpoch;
        uint256 start;
        uint256 end;
        uint256 lastClaimedEpoch;
    }

    struct ContractAddresses {
        address magic;
        address gFly;
        address atlasStaker;
        address founderVaultV1;
        address founderVaultV2;
        address flywheelEmissions;
        address foundersToken;
        address magicSwapRouter;
        address magicGflyLp;
        address exceptionAddress;
        address dao;
        address battleflyBot;
    }

    function burnTokens(uint256[] calldata tokenIds) external;

    function distributeBurnPayouts() external;

    function claimable(uint256 positionId) external view returns (uint256);

    function claimableForAccount(address account) external view returns (uint256);

    function claim(uint256 positionId) external;

    function claimAll() external;

    function topupGFly(uint256 amount) external;

    function withdrawGFly(uint256 amount) external;

    function pause() external;

    function unpause() external;

    function setSlippageInBPS(uint256 slippageInBPS_) external;

    function setNonRewardBurnAddress(address nonRewardBurnAddress) external;

    function setPauseGuardian(address account, bool state) external;

    function isPauseGuardian(address account) external view returns (bool);

    function burnPositionsOfAccount(address account) external view returns (uint256[] memory);

    function treasuryOwnedMagicFromBurns() external view returns (uint256);

    function currentV1BackingInMagic() external view returns (uint256);

    function currentV2BackingInMagic() external view returns (uint256);

    // ========== Events ==========
    event BurnPositionCreated(
        address account,
        uint256 positionId,
        uint256 amountPerEpoch,
        uint256 totalAmount,
        uint256 start,
        uint256 end,
        bool fromLiquidAmount
    );
    event BurnPayoutsDistributed(uint256 currentEpoch);
    event PositionClaimed(address account, uint256 positionId, uint256 claimable);
    event PauseStateChanged(bool state);

    // ========== Errors ==========
    error ContractPaused();
    error AccessDenied();
    error AlreadyUnPaused();
    error InvalidAddress();
    error IdenticalAddresses();
    error InvalidOwner();
}


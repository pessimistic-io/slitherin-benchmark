// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGameV2 {
    function setMagic(address magicAddress) external;

    function setWithdrawalLimit(uint256 withdrawalLimit_) external;

    function setAdminAccess(address user, bool access) external;

    function topupWastelandsRewards(uint256 amount) external;

    function setWastelandsContract(address wastelands) external;

    function withdrawMagicForRNGEmissions(uint256 amount) external;

    function setGameDiamondContract(address gameDiamond) external;

    function addPauseGuardian(address pauseGuardian) external;

    function removePauseGuardian(address pauseGuardian) external;

    function processPendingWithdrawal(uint256 pendingId, bool authorize) external;

    //Magic token
    function depositMagic(uint256 amount) external;

    function topupLeaderboardRewards(uint256 amount) external;

    function claimWithdrawMagic(
        uint256 amount,
        uint256 transactionId,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function pause() external;

    function unpause() external;
}


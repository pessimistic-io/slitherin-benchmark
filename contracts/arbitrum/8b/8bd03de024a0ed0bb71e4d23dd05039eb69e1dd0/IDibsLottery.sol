// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

struct LeaderBoard {
    uint32 lastUpdatedDay; // day from start of the round that the leaderBoard data was last updated
    uint8 count; // number of users in the leaderBoard
    address[] rewardTokens;
    uint256[][] rankRewardAmount; // (tokenPosition => (rank => reward amount))
}

interface IDibsLottery {
    function getActiveLotteryRound() external view returns (uint32);

    function roundDuration() external view returns (uint32);

    function firstRoundStartTime() external view returns (uint32);

    function roundToWinner(uint32) external view returns (address);

    function setRoundWinners(uint32 roundId, address[] memory winners) external;

    function setTopReferrers(
        uint32 day,
        address[] memory topReferrers
    ) external;

    function getLatestLeaderBoard() external view returns (LeaderBoard memory);
}


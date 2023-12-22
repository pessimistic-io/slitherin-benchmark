// SPDX-License-Identifier: MIT

import { IERC20 } from "./IERC20.sol";
import { ISnapshottable } from "./ISnapshottable.sol";

pragma solidity ^0.8.0;


struct UserStake {
    uint256 amount;
    uint256 depositBlock;
    uint256 withdrawBlock;
    uint256 emergencyWithdrawalBlock;

    uint256 lastSnapshotBlockNumber;
}


interface IStaking is ISnapshottable {
    function getStake(address) external view returns (UserStake memory);
    function isPenaltyCollector(address) external view returns (bool);
    function token() external view returns (IERC20);
    function penalty() external view returns (uint256);

    function stake(uint256 amount) external;
    function stakeFor(address account, uint256 amount) external;
    function withdraw(uint256 amount) external;
    function emergencyWithdraw(uint256 amount) external;
    function changeOwner(address newOwner) external;
    function sendPenalty(address to) external returns (uint256);
    function setPenaltyCollector(address collector, bool status) external;
    function getVestedTokens(address user) external view returns (uint256);
    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external view returns (uint256);
    function getWithdrawable(address user) external view returns (uint256);
    function getEmergencyWithdrawPenalty(address user) external view returns (uint256);
    function getVestedTokensPercentage(address user) external view returns (uint256);
    function getWithdrawablePercentage(address user) external view returns (uint256);
    function getEmergencyWithdrawPenaltyPercentage(address user) external view returns (uint256);
    function getEmergencyWithdrawPenaltyAmountReturned(address user, uint256 amount) external view returns (uint256);
}


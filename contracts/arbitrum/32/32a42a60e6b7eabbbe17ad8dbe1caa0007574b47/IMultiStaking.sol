// SPDX-License-Identifier: MIT

import { IERC20 } from "./IERC20.sol";
import { ISnapshottable } from "./ISnapshottable.sol";

pragma solidity ^0.8.0;


struct UserStake {
    uint256 amount;
    uint256 depositBlock;
    uint256 withdrawBlock;
    uint256 emergencyWithdrawalBlock;
}


interface IMultiStaking is ISnapshottable {
    function baseToken() external view returns (IERC20);

    function getStake(address account, IERC20 _token) external view returns (UserStake memory);
    function token() external view returns (IERC20);
    function penalty(IERC20 _token) external view returns (uint256);
    function isTokenWhitelisted(IERC20 token) external view returns (bool);
    function isAllTokensWhitelisted() external view returns (bool);

    function stake(IERC20 _token, uint256 _amount) external;

    function stakeFor(address _account, uint256 _amount) external;
    function stakeFor(address _account, IERC20 _token, uint256 _amount) external;

    function withdraw(IERC20 _token, uint256 _amount) external;

    function emergencyWithdraw(IERC20 _token, uint256 _amount) external;

    function sendPenalty(address to, IERC20 _token) external returns (uint256);

    function getVestedTokens(address user, IERC20 _token) external view returns (uint256);

    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external view returns (uint256);

    function getWithdrawable(address user, IERC20 _token) external view returns (uint256);

    function getEmergencyWithdrawPenalty(address user, IERC20 _token) external view returns (uint256);

    function getVestedTokensPercentage(address user, IERC20 _token) external view returns (uint256);
    
    function getWithdrawablePercentage(address user, IERC20 _token) external view returns (uint256);

    function getEmergencyWithdrawPenaltyPercentage(address user, IERC20 _token) external view returns (uint256);

    function getEmergencyWithdrawPenaltyAmountReturned(address user, IERC20 _token, uint256 amount) external view returns (uint256);

    function getStakersCount() external view returns (uint256);
    function getStakersCount(IERC20 _token) external view returns (uint256);

    function getStakers(uint256 idx) external view returns (address);
    function getStakers(IERC20 _token, uint256 idx) external view returns (address);

    function userTokens(address user, uint256 idx) external view returns (IERC20);
    function getUserTokens(address user) external view returns (IERC20[] memory);

    function tokens(uint256 idx) external view returns (IERC20);
    function tokensLength() external view returns (uint256);
}

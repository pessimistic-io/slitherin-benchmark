// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IRankerRewardDistributor {
    function withdrawTokens() external;
    function withdrawToLocker() external;

    function tokensClaimable(address _user) external view returns (uint256 claimableAmount);
    function tokensLockable(address _user) external view returns (uint256 lockableAmount);
    function getTokenAmount(address _user) external view returns (uint256);
}

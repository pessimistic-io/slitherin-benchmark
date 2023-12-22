// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

interface IGenesisRewardDistributor {
    function withdrawTokens() external;
    function withdrawToLocker() external;

    function tokensClaimable(address _user) external view returns (uint256 claimableAmount);
    function tokensLockable(address _user) external view returns (uint256 lockableAmount);
}


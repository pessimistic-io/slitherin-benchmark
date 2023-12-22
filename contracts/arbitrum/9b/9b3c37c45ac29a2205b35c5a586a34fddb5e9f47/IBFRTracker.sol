// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBFRTracker {
    function claim(address receiver) external;
    function claimable(address user) external view returns (uint256);
    function depositBalances(address user, address token) external view returns (uint256);
    function stakeForAccount(
        address _fundingAccount,
        address _account,
        address _depositToken,
        uint256 _amount
    ) external;
    function unstakeForAccount(
        address _account,
        address _depositToken,
        uint256 _amount,
        address _receiver
    ) external;
}


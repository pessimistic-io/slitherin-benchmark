// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// For interacting with our own strategy
interface IStrategy {
    // Total want tokens managed by stratfegy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // amount: Total want tokens managed by stratfegy
    // shares: Sum of all shares of users to wantLockedTotal
    function sharesInfo() external view returns (uint256, uint256);

    // Main want token compounding function
    function earn() external;

    // Transfer want tokens autoFarm -> strategy
    function deposit(address _userAddress, uint256 _wantAmt)
        external
        returns (uint256);

    // Transfer want tokens strategy -> autoFarm
    function withdraw(address _userAddress, uint256 _wantAmt)
        external
        returns (uint256);

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;

    function accInterestPerShare() external view returns (uint256);
    function updatePool() external returns (uint256);
    function distributeRewards(address _to, uint256 _amount) external returns (uint256);

    function onRewardEarn(address _user, uint256 _amount) external;

    struct EarnInfo {
        address token;
        uint256 amount;
    }
    function pendingEarn(address _user) external view returns (EarnInfo[] memory);
}


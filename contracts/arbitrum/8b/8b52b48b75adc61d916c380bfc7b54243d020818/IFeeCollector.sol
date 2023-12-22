// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IFeeCollector {
    function balanceLockExpires(address account) external view returns (uint);
    function balanceOf(address account) external returns (uint);
    function deposit(address account, uint amount) external;
    function earned(address token, address account) external view returns (uint);
    function getEpochStart(uint timestamp) external pure returns (uint);
    function getReward(address[] memory tokens) external;
    function isBalanceLockExpired(address account) external view returns (bool);
    function left(address token) external view returns (uint);
    function notifyRewardAmount(address token, uint amount) external;
    function withdraw(address account, uint amount) external;
}

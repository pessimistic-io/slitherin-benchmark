// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./IERC20.sol";

interface ICollSurplusPool {

    function getTotalCollateral() external view returns (uint);

    function getUserCollateral(address _account) external view returns (uint);

    function claimColl(IERC20 _depositToken, address _account) external;

    function accountSurplus(address _account, uint _amount) external;
}

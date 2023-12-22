// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;

interface IRewardRouter {
    function stakeLpForAccount(address _account, address _lp, uint256 _amount) external returns (uint256);

    function unstakeLpForAccount(address _account, address _lp, uint256 _amount) external returns (uint256);
}


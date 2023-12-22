// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.18;

import "./IMintableToken.sol";

interface IRewardTracker is IMintableToken {
    function stakedAmount(address account) external returns (uint);

    function lockedAmount(address account) external returns (uint);

    function boostedAmount(address account) external returns (uint);

    function updateRewards() external;

    function claimForAccount(address account) external;

    function claim(uint _lockTime) external;

    function deposit(uint amount, uint _lockTime) external;

    function withdraw(uint amount, uint _lockTime) external;
}


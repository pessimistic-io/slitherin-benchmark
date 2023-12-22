pragma solidity 0.8.18;

// SPDX-License-Identifier: MIT

interface IBoosting {
    function getBoostMultiplier(address _user, uint256 _pid) external view returns (uint256 BoostMultiplier);

    function getBoostMultiplierWithDeposit(
        address _user,
        uint256 _pid,
        uint256 _amount
    ) external view returns (uint256 BoostMultiplier);

    function getBoostMultiplierWithWithdrawal(
        address _user,
        uint256 _pid,
        uint256 _amount
    ) external view returns (uint256 BoostMultiplier);
}


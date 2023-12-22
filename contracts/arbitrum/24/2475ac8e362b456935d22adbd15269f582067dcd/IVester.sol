// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface IVester {
    function bonusRewards(address _account) external view returns (uint256);

    function setBonusRewards(address _account, uint256 _amount) external;
}


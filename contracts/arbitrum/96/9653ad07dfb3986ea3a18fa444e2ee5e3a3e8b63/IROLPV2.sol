// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IROLPV2 {
    function cooldownDurations(address _caller) external returns (uint256);

    function mintWithCooldown(address _account, uint256 _amount, uint256 _cooldown) external;
}

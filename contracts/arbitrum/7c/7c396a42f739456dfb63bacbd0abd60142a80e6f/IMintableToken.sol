// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

interface IMintableToken {
    function burn(address _account, uint256 _amount) external returns (uint256);
}


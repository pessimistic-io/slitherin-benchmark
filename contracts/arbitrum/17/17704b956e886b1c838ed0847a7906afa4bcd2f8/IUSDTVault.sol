// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUSDTVault {
    function finalizeGame(address _player, uint256 _prize, uint256 _fee) external payable;
}


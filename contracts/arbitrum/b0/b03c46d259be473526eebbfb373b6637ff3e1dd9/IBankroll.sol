// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBankroll {
    function getIsGame(address game) external view returns (bool);

    function getIsValidWager(address game, address tokenAddress) external view returns (bool);

    function transferPayout(address player, uint256 payout, address token) external;

    function owner() external view returns (address);

    function payoutL2E(
        address player,
        address wagerToken,
        uint256 wager,
        uint256 payout
    ) external returns (uint256 l2eAmount);
}


// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

interface IUserAccount {
    function settleLastTimestamp() external;

    function openPosition(
        address clearingHouse,
        address baseToken,
        bool isBaseToQuote,
        uint256 quote
    ) external returns (bool);

    function closePosition(address clearingHouse, address baseToken) external returns (bool);

    function withdrawAll(address clearingHouse, address baseToken) external returns (address token, uint256 amount);

    function withdraw(
        address clearingHouse,
        address baseToken,
        uint256 amountArg
    ) external returns (address token, uint256 amount);

    function claimReward(address clearingHouse) external returns (uint256 amount);
}


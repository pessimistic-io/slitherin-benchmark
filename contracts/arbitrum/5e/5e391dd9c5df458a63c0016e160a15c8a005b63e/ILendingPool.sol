// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface ILendingPool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external;

    function getReserveData(address asset)
        external
        view
        returns (
            uint256,
            uint128,
            uint128,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16,
            address
        );
}

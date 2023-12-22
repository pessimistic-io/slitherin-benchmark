// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

interface IVaultFeesAndHooks {

    function getVaultRebalanceFees(
            address vault,
            uint256 lastRebalance
        ) external pure returns (
            uint256,
            uint256,
            uint256,
            uint256);

    function getWithdrawalFee(
            address vault,
            uint256 size
        ) external pure returns (
            uint256);

    function getDepositFee(
            uint256 size
        ) external pure returns (
            uint256);

    function beforeOpenRebalancePeriod(
            bytes memory _calldata
        ) external;

    function afterCloseRebalancePeriod(
            bytes memory _calldata
        ) external;
}

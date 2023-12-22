// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;


interface IPledgeManager {

    struct Collateral {
        address token;
        uint256 amount;
    }

    function openPledge(
        uint256 _pledgeId,
        uint256 _debt,
        Collateral[] memory _colls,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function updatePledge(
        uint256 _pledgeId,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _accruedFees,
        Collateral[] memory _collsIn,
        Collateral[] memory _collsOut,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;
}


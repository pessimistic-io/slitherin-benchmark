// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

interface IVault {
    function transferToCDX(
        address _token_address,
        uint256 _amount,
        uint256 _customerId,
        uint256 _pid,
        uint256 _purchaseProductAmount,
        uint256 _releaseHeight
    ) external;

    function hedgeTreatment(
        bool _isSell,
        address _token,
        uint256 _amount,
        uint256 _releaseHeight
    ) external returns (bool);
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

interface ICrucibleToken {
    enum OverrideState {
        Default,
        OverrideIn,
        OverrideOut,
        OverrideBoth
    }

    function deposit(address to) external returns (uint256);

    function withdraw(address to, uint256 amount)
        external
        returns (uint256, uint256);

    function baseToken() external returns (address);

    function overrideFee(
        address target,
        OverrideState overrideType,
        uint64 newFeeX10000
    ) external;

    function updateCrucibleFees(
        uint64 newFeeOnTransferX10000,
        uint64 newFeeOnWithdrawX10000
    ) external;

    function upgradeRouter(address router) external;
}


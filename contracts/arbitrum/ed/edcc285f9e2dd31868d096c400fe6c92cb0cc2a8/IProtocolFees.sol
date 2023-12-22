// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title IProtocolFees - ProtocolFees interface
interface IProtocolFees {
    // =========================
    // Events
    // =========================

    /// @notice Emits when instant fees are changed.
    event InstantFeesChanged(uint64 instantFeeGasBps, uint192 instantFeeFix);

    /// @notice Emits when automation fees are changed.
    event AutomationFeesChanged(
        uint64 automationFeeGasBps,
        uint192 automationFeeFix
    );

    /// @notice Emits when treasury address are changed.
    event TreasuryChanged(address treasury);

    // =========================
    // Getters
    // =========================

    /// @notice Gets instant fees.
    /// @return treasury address of the ditto treasury
    /// @return instantFeeGasBps instant fee in gas bps
    /// @return instantFeeFix fixed fee for instant calls
    function getInstantFeesAndTreasury()
        external
        view
        returns (
            address treasury,
            uint256 instantFeeGasBps,
            uint256 instantFeeFix
        );

    /// @notice Gets automation fees.
    /// @return treasury address of the ditto treasury
    /// @return automationFeeGasBps automation fee in gas bps
    /// @return automationFeeFix fixed fee for automation calls
    function getAutomationFeesAndTreasury()
        external
        view
        returns (
            address treasury,
            uint256 automationFeeGasBps,
            uint256 automationFeeFix
        );

    // =========================
    // Setters
    // =========================

    /// @notice Sets instant fees.
    /// @param instantFeeGasBps: instant fee in gas bps
    /// @param instantFeeFix: fixed fee for instant calls
    function setInstantFees(
        uint64 instantFeeGasBps,
        uint192 instantFeeFix
    ) external;

    /// @notice Sets automation fees.
    /// @param automationFeeGasBps: automation fee in gas bps
    /// @param automationFeeFix: fixed fee for automation calls
    function setAutomationFee(
        uint64 automationFeeGasBps,
        uint192 automationFeeFix
    ) external;

    /// @notice Sets the ditto treasury address.
    /// @param treasury: address of the ditto treasury
    function setTreasury(address treasury) external;
}


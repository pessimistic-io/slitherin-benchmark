// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "./Ownable.sol";
import {TransferHelper} from "./TransferHelper.sol";

import {IProtocolFees} from "./IProtocolFees.sol";

/// @title ProtocolFees
contract ProtocolFees is IProtocolFees, Ownable {
    // =========================
    // Storage
    // =========================

    /// @dev ditto treasury address
    address private _treasury;

    /// @dev instant fee in gas bps, 1e18 == 100%
    /// @dev e.g. gasUsed * instantFeeGasBps / 1e18
    uint64 private _instantFeeGasBps; //

    /// @dev fixed fee for transactions
    uint192 private _instantFeeFix;

    /// @dev automation fee in gas bps, 1e18 == 100%
    /// @dev e.g. gasUsed * automationFeeGasBps / 1e18
    uint64 private _automationFeeGasBps;

    /// @dev fixed fee for transactions
    uint192 private _automationFeeFix; //

    // =========================
    // Constructor
    // =========================

    constructor(address owner) {
        _transferOwnership(owner);
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IProtocolFees
    function getInstantFeesAndTreasury()
        external
        view
        returns (
            address treasury,
            uint256 instantFeeGasBps,
            uint256 instantFeeFix
        )
    {
        treasury = _treasury;
        instantFeeGasBps = _instantFeeGasBps;
        instantFeeFix = _instantFeeFix;
    }

    /// @inheritdoc IProtocolFees
    function getAutomationFeesAndTreasury()
        external
        view
        returns (
            address treasury,
            uint256 automationFeeGasBps,
            uint256 automationFeeFix
        )
    {
        treasury = _treasury;
        automationFeeGasBps = _automationFeeGasBps;
        automationFeeFix = _automationFeeFix;
    }

    // =========================
    // Setters
    // =========================

    /// @inheritdoc IProtocolFees
    function setInstantFees(
        uint64 instantFeeGasBps,
        uint192 instantFeeFix
    ) external onlyOwner {
        _instantFeeGasBps = instantFeeGasBps;
        _instantFeeFix = instantFeeFix;

        emit InstantFeesChanged(instantFeeGasBps, instantFeeFix);
    }

    /// @inheritdoc IProtocolFees
    function setAutomationFee(
        uint64 automationFeeGasBps,
        uint192 automationFeeFix
    ) external onlyOwner {
        _automationFeeGasBps = automationFeeGasBps;
        _automationFeeFix = automationFeeFix;

        emit AutomationFeesChanged(automationFeeGasBps, automationFeeFix);
    }

    /// @inheritdoc IProtocolFees
    function setTreasury(address treasury) external onlyOwner {
        _treasury = treasury;

        emit TreasuryChanged(treasury);
    }
}


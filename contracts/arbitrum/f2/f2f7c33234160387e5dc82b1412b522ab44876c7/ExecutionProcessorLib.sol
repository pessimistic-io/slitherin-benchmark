//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "./SafeCastUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./SignedMathUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IFeeModel.sol";
import "./CodecLib.sol";
import "./StorageLib.sol";
import "./TransferLib.sol";

import {InvalidInstrument} from "./ErrorLib.sol";

/// @title ExecutionProcessorLib
/// @dev This set of methods process the result of an execution, update the internal accounting and transfer funds if required
/// @author Bruno Bonanno
library ExecutionProcessorLib {
    using SafeCastUpgradeable for uint256;
    using MathUpgradeable for uint256;
    using SignedMathUpgradeable for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using TransferLib for IERC20Upgradeable;
    using CodecLib for uint256;

    event PositionUpserted(
        address indexed trader,
        PositionId indexed positionId,
        uint256 openQuantity,
        uint256 openCost,
        int256 collateral,
        uint256 totalFees,
        uint256 txFees,
        int256 realisedPnL
    );

    event PositionLiquidated(
        PositionId indexed positionId,
        uint256 openQuantity,
        uint256 openCost,
        int256 collateral,
        int256 realisedPnL
    );

    // TODO Review attributes, maybe remove open* and collateral attributes and move txFees to ContractTraded event (Fees task)
    event PositionClosed(
        address indexed trader,
        PositionId indexed positionId,
        uint256 closedQuantity,
        uint256 closedCost,
        int256 collateral,
        uint256 totalFees,
        uint256 txFees,
        int256 realisedPnL
    );

    event PositionDelivered(
        address indexed trader,
        PositionId indexed positionId,
        address to,
        uint256 deliveredQuantity,
        uint256 deliveryCost,
        uint256 totalFees
    );

    error Undercollateralised(PositionId positionId);
    error PositionIsTooSmall(uint256 openCost, uint256 minCost);

    uint256 public constant MIN_DEBT_MULTIPLIER = 5;

    function deliverPosition(
        PositionId positionId,
        address trader,
        uint256 deliverableQuantity,
        uint256 deliveryCost,
        address payer,
        IERC20Upgradeable quoteToken,
        address to
    ) internal {
        delete StorageLib.getPositionNotionals()[positionId];

        mapping(PositionId => uint256) storage balances = StorageLib.getPositionBalances();
        (, uint256 protocolFees) = balances[positionId].decodeU128();
        delete balances[positionId];

        quoteToken.transferOut(payer, ConfigStorageLib.getTreasury(), protocolFees);

        emit PositionDelivered(trader, positionId, to, deliverableQuantity, deliveryCost, protocolFees);
    }

    function updateCollateral(
        PositionId positionId,
        address trader,
        int256 cost,
        int256 amount
    ) internal {
        (uint256 openQuantity, uint256 openCost) = StorageLib.getPositionNotionals()[positionId].decodeU128();
        (int256 collateral, uint256 protocolFees, uint256 fee) = _applyFees(
            trader,
            positionId,
            cost.abs() + amount.abs()
        );

        openCost = uint256(int256(openCost) + cost);
        collateral = collateral + amount;

        _updatePosition(positionId, trader, openQuantity, openCost, collateral, protocolFees, fee, 0);
    }

    function increasePosition(
        PositionId positionId,
        address trader,
        uint256 size,
        uint256 cost,
        int256 collateralDelta,
        IERC20Upgradeable quoteToken,
        address to,
        uint256 minCost
    ) internal {
        (uint256 openQuantity, uint256 openCost) = StorageLib.getPositionNotionals()[positionId].decodeU128();
        int256 positionCollateral;
        uint256 protocolFees;
        uint256 fee;

        // For a new position
        if (openQuantity == 0) {
            fee = StorageLib.getInstrumentFeeModel(positionId).calculateFee(trader, positionId, cost);
            positionCollateral = collateralDelta - int256(fee);
            protocolFees = fee;
        } else {
            (positionCollateral, protocolFees, fee) = _applyFees(trader, positionId, cost);
            positionCollateral = positionCollateral + collateralDelta;

            // When increasing positions, the user can request to withdraw part (or all) the free collateral
            if (collateralDelta < 0 && address(this) != to) {
                quoteToken.transferOut(address(this), to, uint256(-collateralDelta));
            }
        }

        openCost = openCost + cost;
        _validateMinCost(openCost, minCost);
        openQuantity = openQuantity + size;

        _updatePosition(positionId, trader, openQuantity, openCost, positionCollateral, protocolFees, fee, 0);
    }

    function decreasePosition(
        PositionId positionId,
        address trader,
        uint256 size,
        uint256 cost,
        int256 collateralDelta,
        IERC20Upgradeable quoteToken,
        address to,
        uint256 minCost
    ) internal {
        (uint256 openQuantity, uint256 openCost) = StorageLib.getPositionNotionals()[positionId].decodeU128();
        (int256 collateral, uint256 protocolFees, uint256 fee) = _applyFees(trader, positionId, cost);

        // Proportion of the openCost based on the size of the fill respective of the overall position size
        uint256 closedCost = (size * openCost).ceilDiv(openQuantity);
        int256 pnl = int256(cost) - int256(closedCost);
        openCost = openCost - closedCost;
        _validateMinCost(openCost, minCost);
        openQuantity = openQuantity - size;

        // Crystallised PnL is accounted on the collateral
        collateral = collateral + pnl + collateralDelta;

        // When decreasing positions, the user can request to withdraw part (or all) the proceedings
        if (collateralDelta < 0 && address(this) != to) {
            quoteToken.transferOut(address(this), to, uint256(-collateralDelta));
        }

        _updatePosition(positionId, trader, openQuantity, openCost, collateral, protocolFees, fee, pnl);
    }

    function closePosition(
        PositionId positionId,
        address trader,
        uint256 cost,
        IERC20Upgradeable quoteToken,
        address to
    ) internal {
        mapping(PositionId => uint256) storage notionals = StorageLib.getPositionNotionals();
        (uint256 openQuantity, uint256 openCost) = notionals[positionId].decodeU128();
        (int256 collateral, uint256 protocolFees, uint256 fee) = _applyFees(trader, positionId, cost);

        int256 pnl = int256(cost) - int256(openCost);

        // Crystallised PnL is accounted on the collateral
        collateral = collateral + pnl;

        delete notionals[positionId];
        delete StorageLib.getPositionBalances()[positionId];

        quoteToken.transferOut(address(this), ConfigStorageLib.getTreasury(), protocolFees);
        if (collateral > 0 && to != address(this)) {
            quoteToken.transferOut(address(this), to, uint256(collateral));
        }

        emit PositionClosed(trader, positionId, openQuantity, openCost, collateral, protocolFees, fee, pnl);
    }

    function liquidatePosition(
        PositionId positionId,
        uint256 size,
        uint256 cost
    ) internal {
        mapping(PositionId => uint256) storage notionals = StorageLib.getPositionNotionals();
        mapping(PositionId => uint256) storage balances = StorageLib.getPositionBalances();
        (uint256 openQuantity, uint256 openCost) = notionals[positionId].decodeU128();
        (int256 collateral, int256 protocolFees) = balances[positionId].decodeI128();

        // Proportion of the openCost based on the size of the fill respective of the overall position size
        uint256 closedCost = size == openQuantity ? openCost : (size * openCost).ceilDiv(openQuantity);
        int256 pnl = int256(cost) - int256(closedCost);
        openCost = openCost - closedCost;
        openQuantity = openQuantity - size;

        // Crystallised PnL is accounted on the collateral
        collateral = collateral + pnl;

        notionals[positionId] = CodecLib.encodeU128(openQuantity, openCost);
        balances[positionId] = CodecLib.encodeI128(collateral, protocolFees);
        emit PositionLiquidated(positionId, openQuantity, openCost, collateral, pnl);
    }

    // ============= Private functions ================

    function _applyFees(
        address trader,
        PositionId positionId,
        uint256 cost
    )
        private
        view
        returns (
            int256 collateral,
            uint256 protocolFees,
            uint256 fee
        )
    {
        int256 iProtocolFees;
        (collateral, iProtocolFees) = StorageLib.getPositionBalances()[positionId].decodeI128();
        protocolFees = uint256(iProtocolFees);
        fee = StorageLib.getInstrumentFeeModel(positionId).calculateFee(trader, positionId, cost);
        collateral = collateral - int256(fee);
        protocolFees = protocolFees + fee;
    }

    function _updatePosition(
        PositionId positionId,
        address trader,
        uint256 openQuantity,
        uint256 openCost,
        int256 collateral,
        uint256 protocolFees,
        uint256 fee,
        int256 pnl
    ) private {
        StorageLib.getPositionNotionals()[positionId] = CodecLib.encodeU128(openQuantity, openCost);
        StorageLib.getPositionBalances()[positionId] = CodecLib.encodeI128(collateral, int256(protocolFees));
        emit PositionUpserted(trader, positionId, openQuantity, openCost, collateral, protocolFees, fee, pnl);
    }

    function _validateMinCost(uint256 openCost, uint256 minCost) private pure {
        if (openCost < minCost * MIN_DEBT_MULTIPLIER) {
            revert PositionIsTooSmall(openCost, minCost * MIN_DEBT_MULTIPLIER);
        }
    }
}


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IFeeStrategy} from "./IFeeStrategy.sol";

contract FeeStrategy is Ownable, IFeeStrategy {
    /// @dev Purchase Fee: x% of the price of the underlying asset * the amount of options being bought * OTM Fee Multiplier
    uint256 public purchaseFeePercentage = 125e8 / 1000; // 0.125%

    /// @dev Settlement Fee: x% of the settlement price
    uint256 public settlementFeePercentage = 125e8 / 1000; // 0.125%

    event PurchaseFeePercentageUpdate(uint256 newFee);

    event SettlementFeePercentageUpdate(uint256 newFee);

    /// @notice Update the purchase fee percentage
    /// @dev Can only be called by owner
    /// @param newFee The new fee
    /// @return Whether it was successfully updated
    function updatePurchaseFeePercentage(uint256 newFee)
        external
        onlyOwner
        returns (bool)
    {
        purchaseFeePercentage = newFee;
        emit PurchaseFeePercentageUpdate(newFee);
        return true;
    }

    /// @notice Update the settlement fee percentage
    /// @dev Can only be called by owner
    /// @param newFee The new fee
    /// @return Whether it was successfully updated
    function updateSettlementFeePercentage(uint256 newFee)
        external
        onlyOwner
        returns (bool)
    {
        settlementFeePercentage = newFee;
        emit SettlementFeePercentageUpdate(newFee);
        return true;
    }

    /// @notice Calculate Fees for purchase
    /// @param price settlement price of DPX
    /// @param strike total pnl
    /// @param amount amount of options being bought
    function calculatePurchaseFees(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) external view returns (uint256 finalFee) {
        finalFee = (purchaseFeePercentage * amount) / 1e10;

        if (price < strike) {
            uint256 feeMultiplier = (((strike * 100) / (price)) - 100) + 100;
            finalFee = (feeMultiplier * finalFee) / 100;
        }
    }

    /// @notice Calculate Fees for settlement
    function calculateSettlementFees(
        uint256,
        uint256,
        uint256
    ) external view returns (uint256 finalFee) {
        finalFee = settlementFeePercentage * 0;
    }
}


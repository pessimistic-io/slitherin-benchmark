// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";

// Interfaces
import {IFeeStrategy} from "./IFeeStrategy.sol";

contract SsovV3FeeStrategy is Ownable, IFeeStrategy {
    struct FeeStructure {
        /// @dev Purchase Fee in 1e8: x% of the price of the underlying asset * the amount of options being bought
        uint256 purchaseFeePercentage;
        /// @dev Settlement Fee in 1e8: x% of the settlement price
        uint256 settlementFeePercentage;
    }

    /// @dev ssov address => FeeStructure
    mapping(address => FeeStructure) public ssovFeeStructures;

    /// @notice Emitted on update of a ssov fee structure
    /// @param ssov address of ssov
    /// @param feeStructure FeeStructure of the ssov
    event FeeStructureUpdated(address ssov, FeeStructure feeStructure);

    /// @notice Update the fee structure of an ssov
    /// @dev Can only be called by owner
    /// @param ssov target ssov
    /// @param feeStructure FeeStructure for the ssov
    function updateSsovFeeStructure(
        address ssov,
        FeeStructure calldata feeStructure
    ) external onlyOwner {
        ssovFeeStructures[ssov] = feeStructure;
        emit FeeStructureUpdated(ssov, feeStructure);
    }

    /// @notice Calculate Fees for purchase
    /// @param price price of underlying in 1e8 precision
    /// @param strike strike price of the option in 1e8 precision
    /// @param amount amount of options being bought in 1e18 precision
    /// @param finalFee in USD in 1e8 precision
    function calculatePurchaseFees(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) external view returns (uint256 finalFee) {
        (uint256 purchaseFeePercentage, ) = getSsovFeeStructure(msg.sender);

        finalFee = ((purchaseFeePercentage * amount * price) / 1e10) / 1e18;

        if (price < strike) {
            uint256 feeMultiplier = (((strike * 100) / (price)) - 100) + 100;
            finalFee = (feeMultiplier * finalFee) / 100;
        }
    }

    /// @notice Calculate Fees for settlement
    /// @param pnl PnL of the settlement
    /// @return finalFee in the precision of pnl
    function calculateSettlementFees(uint256 pnl)
        external
        view
        returns (uint256 finalFee)
    {
        (, uint256 settlementFeePercentage) = getSsovFeeStructure(msg.sender);

        finalFee = (settlementFeePercentage * pnl) / 1e10;
    }

    /// @notice Returns the fee structure of an ssov
    /// @param ssov target ssov
    function getSsovFeeStructure(address ssov)
        public
        view
        returns (uint256 purchaseFeePercentage, uint256 settlementFeePercentage)
    {
        FeeStructure memory feeStructure = ssovFeeStructures[ssov];

        purchaseFeePercentage = feeStructure.purchaseFeePercentage;
        settlementFeePercentage = feeStructure.settlementFeePercentage;
    }
}


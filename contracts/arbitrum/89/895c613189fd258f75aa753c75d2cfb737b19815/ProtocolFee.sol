// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./SafeERC20.sol";

abstract contract ProtocolFee {
    using SafeERC20 for IERC20;

    /// @dev Fee type variants: percentage fee and flat fee
    enum FeeType {
        Bps,
        Flat
    }

    struct Fee {
        FeeType feeType;
        uint16 feeBps;          // The % of fees. (Basis Points)
        uint256 flatFee;        // The flat amount as fees.
        address feeRecipient;
    }

    uint256 public constant MAX_BPS = 10_000;

    event FeeInfoAdded(uint8 indexed index, Fee fee);
    event FeeInfoUpdated(uint8 indexed index, Fee fee);
    event FeeCharged(uint8 indexed index, Fee fee, IERC20 token, uint256 totalAmount, uint256 feeAmount);
    
    mapping(uint8 => Fee) _fees;
    
    function getMaxBps() public pure returns (uint256 maxBps) {
        return MAX_BPS;
    }

    function getFeeInfo(uint8 index) public view virtual returns (Fee memory) {
        return _fees[index];
    }

    function _checkFeeInfo(Fee memory fee) private view {
        require(_canSetFeeInfo(), "Not authorized"); 
        require(fee.feeBps < MAX_BPS, "Exceeds max mng bps");
    }

    function addFeeInfo(uint8 index, Fee memory fee) public virtual {
       _checkFeeInfo(fee);

        _fees[index] = fee;

       emit FeeInfoAdded(index, fee);
    }

    function updateFeeInfo(uint8 index, Fee memory fee) public virtual {
        _checkFeeInfo(fee);
  
        _fees[index] = fee;

        emit FeeInfoUpdated(index, fee);
    }

    function previewFeeAmount(uint8 index, uint256 totalAmount) public view returns (uint256 feeAmount) {
        Fee memory fee = getFeeInfo(index);        
        if (fee.feeType == FeeType.Flat) {
            feeAmount = fee.flatFee;
        } else {
            feeAmount = (totalAmount * fee.feeBps) / MAX_BPS;
        }
    }

    // =============================================================
    //                    INTERNAL HOOKS LOGIC
    // =============================================================
    function _canSetFeeInfo() internal view virtual returns (bool);

    function _chargeFee(IERC20 token, uint8 feeIndex, uint256 totalAmount) internal virtual returns (uint256 feeAmount)
    {        
        Fee memory fee = getFeeInfo(feeIndex);        
        if (fee.feeRecipient == address(0)) return 0;

        feeAmount = previewFeeAmount(feeIndex, totalAmount);
        require(totalAmount >= feeAmount, "Fees greater than price");
            
        token.safeTransfer(fee.feeRecipient, feeAmount);

        emit FeeCharged(feeIndex, fee, token, totalAmount, feeAmount);
    }
}

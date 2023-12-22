// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.19;

// import "forge-std/interfaces/IERC20.sol";
import "./IERC20.sol";

struct Fee {
    uint256 totalAmount;
    uint256 burnAmount;
    uint256 gasAmount;
}

abstract contract FeeCollection {
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Measured in 10000ths. So 125 => 1.25%, 250 => 2.5%, 2500 => 25%
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public feePercentage;

    // integer amount of fee to keep to reimburse oracle for gas
    uint256 public oracleFee;

    // Total fees collected to reimburse oracle for gas
    uint256 public collectedOracleFees;

    // ERC20 we collect fees in
    IERC20 public feeToken;

    function burnFee(uint256 feeAmount) internal {
        if (feeAmount > 0) {
            require(feeToken.transfer(BURN_ADDRESS, feeAmount), "Burn transfer failed");
        }
    }

    // Keep track of collectedFees
    function saveFee(uint256 feeAmount) internal {
        collectedOracleFees += feeAmount;
    }

    // Withdraw collected oracle fees to a recipient
    function withdrawFees(address recipient) internal {
        require(feeToken.transfer(recipient, collectedOracleFees), "Payout transfer failed");
    }

    function setFeeToken(IERC20 _dmt) internal {
        feeToken = _dmt;
    }

    function setFeePercentage(uint256 _feePercentage) internal {
        feePercentage = _feePercentage;
    }

    function setOracleFee(uint256 _oracleFee) internal {
        oracleFee = _oracleFee;
    }

    function calculateFee(uint256 amount) internal view returns (Fee memory) {
        uint256 totalFee = (amount * feePercentage) / FEE_DENOMINATOR;

        if (totalFee < oracleFee) {
            return Fee({totalAmount: totalFee, gasAmount: totalFee, burnAmount: 0});
        } else {
            return Fee({totalAmount: totalFee, gasAmount: oracleFee, burnAmount: totalFee - oracleFee});
        }
    }
}


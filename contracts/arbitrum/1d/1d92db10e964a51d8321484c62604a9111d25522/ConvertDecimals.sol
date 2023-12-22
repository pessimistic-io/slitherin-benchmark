//SPDX-License-Identifier: ISC
pragma solidity ^0.8.0;

// Libraries
import "./Math.sol";

/**
 * @title ConvertDecimals
 * @author Lyra
 * @dev Contract to convert amounts to and from erc20 tokens to 18 dp.
 */
library ConvertDecimals {
    /// @dev Converts amount from a given precisionFactor to 18 dp. This cuts off precision for decimals > 18.
    function normaliseTo18(uint256 amount, uint256 precisionFactor) internal pure returns (uint256) {
        return (amount * 1e18) / precisionFactor;
    }
}


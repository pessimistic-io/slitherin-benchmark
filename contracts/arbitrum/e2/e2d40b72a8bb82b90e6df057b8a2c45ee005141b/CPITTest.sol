// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { CPIT } from "./CPIT.sol";
import { Constants } from "./Constants.sol";

contract CPITTest is CPIT {
    function cpitLockedUntil() public view returns (uint256) {
        return _cpitLockedUntil();
    }

    function isCpitLocked() public view returns (bool) {
        return _isCpitLocked();
    }

    function getCurrentWindow() public view returns (uint256 currentWindow) {
        return _getCurrentWindow();
    }

    function updatePriceImpact(
        uint preTransactionValue,
        uint postTransactionValue,
        uint maxCpitBips
    ) public returns (uint priceImpactBips) {
        return
            _updatePriceImpact(
                preTransactionValue,
                postTransactionValue,
                maxCpitBips
            );
    }

    // calculate the 24 hour cumulative price impact
    function calculateCumulativePriceImpact(
        uint currentWindow
    ) public view returns (uint cumulativePriceImpact) {
        return _calculateCumulativePriceImpact(currentWindow);
    }

    function calculatePriceImpact(
        uint oldValue,
        uint newValue
    ) public pure returns (uint priceImpactBips) {
        return _calculatePriceImpact(oldValue, newValue);
    }
}


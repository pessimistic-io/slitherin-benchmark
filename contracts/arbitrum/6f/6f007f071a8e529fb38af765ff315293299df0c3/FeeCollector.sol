// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {ILBPair} from "./ILBPair.sol";

import {BaseComponent} from "./BaseComponent.sol";
import {IFeeCollector} from "./IFeeCollector.sol";

/**
 * @title Fee Collector
 * @author Trader Joe
 * @notice This contract is used to collect the protocol fees for a given pair.
 */
contract FeeCollector is BaseComponent, IFeeCollector {
    /**
     * @dev Initializes the FeeCollector contract.
     * @param feeManager The fee manager address.
     */
    constructor(address feeManager) BaseComponent(feeManager) {}

    /**
     * @notice Collects the protocol fees for a given pair.
     * @param lbPair The pair to collect the protocol fees for.
     */
    function collectProtocolFees(ILBPair lbPair) external override onlyDelegateCall {
        _collectProtocolFees(lbPair);
    }

    /**
     * @notice Collects the protocol fees for a given list of pairs.
     * @param lbPairs The list of pairs to collect the protocol fees for.
     */
    function batchCollectProtocolFees(ILBPair[] calldata lbPairs) external override onlyDelegateCall {
        for (uint256 i; i < lbPairs.length;) {
            _collectProtocolFees(lbPairs[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Collects the protocol fees for a given pair. Reverts if there are no fees to collect.
     * @param lbPair The pair to collect the protocol fees for.
     */
    function _collectProtocolFees(ILBPair lbPair) private {
        lbPair.collectProtocolFees();
    }
}


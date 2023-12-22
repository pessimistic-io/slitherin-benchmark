// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ArbGasInfo} from "./ArbGasInfo.sol";
import {NodeInterface} from "./NodeInterface.sol";

/// @title L2GasUtil
/// @notice Helper to estimate total gas costs when performing transactions on
///     supported L2 networks.
library L2GasUtil {
    uint256 public constant ARB1_CHAIN_ID = 0xa4b1;
    ArbGasInfo public constant ARB_GAS_INFO = ArbGasInfo(address(0x6c));

    /// @notice Return the price, in wei, to be paid to the L2 per gas unit.
    function getGasPrice() internal view returns (uint256) {
        if (block.chainid == ARB1_CHAIN_ID) {
            (
                ,
                ,
                ,
                ,
                ,
                /** base */
                /** congestion */
                uint256 totalGasPrice
            ) = ARB_GAS_INFO.getPricesInWei();
            return totalGasPrice;
        }

        return tx.gasprice;
    }

    /// @notice Return share of L1 gas fee payable by this tx if on an L2,
    ///     otherwise returns 0
    function getCurrentTxL1GasFees() internal view returns (uint256) {
        if (block.chainid == ARB1_CHAIN_ID) {
            return ARB_GAS_INFO.getCurrentTxL1GasFees();
        }

        return 0;
    }
}


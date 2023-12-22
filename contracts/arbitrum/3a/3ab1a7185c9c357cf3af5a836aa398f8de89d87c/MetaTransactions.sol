// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import { MetaTransactionsFeature } from "./MetaTransactionsFeature.sol";

/**
 * @title MetaTransactions
 * @notice Deploy MetaTransactions using foundry
 */
contract MetaTransactions is MetaTransactionsFeature {
    constructor(address zeroExAddress)
        public
        MetaTransactionsFeature(zeroExAddress) {}
}


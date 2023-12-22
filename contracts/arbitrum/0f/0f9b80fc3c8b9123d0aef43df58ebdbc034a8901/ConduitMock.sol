// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { ConduitInterface } from "./ConduitInterface.sol";

import { TokenTransferrer } from "./TokenTransferrer.sol";

import {     ConduitTransfer,     ConduitBatch1155Transfer } from "./ConduitStructs.sol";

contract ConduitMock is ConduitInterface {
    constructor() {}

    function execute(
        ConduitTransfer[] calldata /* transfers */
    ) external pure override returns (bytes4) {
        // Return the valid magic value.
        return 0x4ce34aa2;
    }

    function executeBatch1155(
        ConduitBatch1155Transfer[] calldata /*  batch1155Transfers */
    ) external view override returns (bytes4 magicValue) {}

    function executeWithBatch1155(
        ConduitTransfer[] calldata, /* standardTransfers */
        ConduitBatch1155Transfer[] calldata /*  batch1155Transfers */
    ) external view override returns (bytes4 magicValue) {}

    function updateChannel(address channel, bool isOpen) external override {}
}


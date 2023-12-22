// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { IProductViewEntry } from "./IProductViewEntry.sol";
import {     IDCSProductEntry } from "./IDCSProductEntry.sol";
import { Transfers } from "./Transfers.sol";
import { IRedepositManager } from "./IRedepositManager.sol";

contract RedepositManager {
    using Transfers for address;

    // CONSTANTS

    uint32 public constant DCS_STRATEGY_ID = 1;

    address public immutable cegaEntry;

    // MODIFIERS

    modifier onlyCegaEntry() {
        require(msg.sender == cegaEntry, "400:NotCegaEntry");
        _;
    }

    // CONSTRUCTOR

    constructor(address _cegaEntry) {
        cegaEntry = _cegaEntry;
    }

    // FUNCTIONS

    receive() external payable {}

    function redeposit(
        uint32 productId,
        address asset,
        uint128 amount,
        address receiver
    ) external onlyCegaEntry {
        uint32 strategyId = IProductViewEntry(cegaEntry).getStrategyOfProduct(
            productId
        );

        if (strategyId == DCS_STRATEGY_ID) {
            address productDepositAsset = IDCSProductEntry(cegaEntry)
                .getDCSProductDepositAsset(productId);
            if (productDepositAsset == asset) {
                // Redeposit
                uint256 value = asset.ensureApproval(cegaEntry, amount);
                IDCSProductEntry(cegaEntry).addToDCSDepositQueue{
                    value: value
                }(productId, amount, receiver);
            } else {
                // Incompatible asset, transfer to receiver
                asset.transfer(receiver, amount);
            }
        } else {
            // Impossible to redeposit, transfer to receiver
            asset.transfer(receiver, amount);
        }
    }
}


// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { IProductViewEntry } from "./IProductViewEntry.sol";
import {     IDCSProductEntry } from "./IDCSProductEntry.sol";
import { ITreasury } from "./ITreasury.sol";
import { Transfers } from "./Transfers.sol";
import { IRedepositManager } from "./IRedepositManager.sol";
import { Errors } from "./Errors.sol";

contract RedepositManager is IRedepositManager {
    using Transfers for address;

    // CONSTANTS

    uint32 public constant DCS_STRATEGY_ID = 1;

    address public immutable cegaEntry;

    // MODIFIERS

    modifier onlyCegaEntry() {
        require(msg.sender == cegaEntry, Errors.NOT_CEGA_ENTRY);
        _;
    }

    // CONSTRUCTOR

    constructor(address _cegaEntry) {
        cegaEntry = _cegaEntry;
    }

    // FUNCTIONS

    receive() external payable {}

    function redeposit(
        ITreasury treasury,
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
                .dcsGetProductDepositAsset(productId);
            if (productDepositAsset == asset) {
                // Redeposit
                treasury.withdraw(asset, address(this), amount, true);
                uint256 value = asset.ensureApproval(cegaEntry, amount);
                try
                    IDCSProductEntry(cegaEntry).dcsAddToDepositQueue{
                        value: value
                    }(productId, amount, receiver)
                {
                    emit Redeposited(productId, asset, amount, receiver, true);
                    return;
                } catch {
                    // Return asset to treasury for withdrawal
                    asset.transfer(address(treasury), amount);
                }
            }
        }

        // Impossible to redeposit, transfer to receiver
        treasury.withdraw(asset, receiver, amount, false);
        emit Redeposited(productId, asset, amount, receiver, false);
    }
}


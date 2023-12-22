// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ITransport } from "./ITransport.sol";
import { IStargateRouter } from "./IStargateRouter.sol";
import { VaultBaseInternal } from "./VaultBaseInternal.sol";
import { Accountant } from "./Accountant.sol";
import { VaultOwnership } from "./VaultOwnership.sol";
import { Registry } from "./Registry.sol";
import { VaultParentStorage } from "./VaultParentStorage.sol";

import { Constants } from "./Constants.sol";

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

import "./console.sol";

contract VaultParentTransport is VaultBaseInternal {
    ///
    /// Receivers/CallBacks
    ///

    function receiveWithdrawComplete() external onlyTransport {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        l.withdrawsInProgress--;
    }

    // Callback for once the sibling has been created on the dstChain
    function receiveSiblingCreated(
        uint16 siblingChainId,
        address siblingVault
    ) external onlyTransport {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        if (l.children[siblingChainId] == address(0)) {
            l.childCreationInProgress = false;
            for (uint8 i = 0; i < l.childChains.length; i++) {
                // Federate the new sibling to the other children
                _registry().transport().sendAddSiblingRequest(
                    ITransport.AddVaultChildRequest({
                        vault: l.children[l.childChains[i]],
                        chainId: l.childChains[i],
                        // The new Sibling
                        newSibling: ITransport.ChildVault({
                            vault: siblingVault,
                            chainId: siblingChainId
                        })
                    })
                );
            }

            l.children[siblingChainId] = siblingVault;
            l.childChains.push(siblingChainId);
        }
    }

    // Callback to notify the parent the bridge has taken place
    function receiveBridgedAssetAcknowledgement() external onlyTransport {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        l.bridgeInProgress = false;
    }

    // Allows the bridge approval to be cancelled by the receiver after a period of time if the bridge doesn't take place
    function receiveBridgeApprovalCancellation() external onlyTransport {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        l.bridgeInProgress = false;
        l.lastBridgeCancellation = block.timestamp;
    }

    // Callback to receive value/supply updates
    function receiveSiblingValue(
        uint16 siblingChainId,
        uint value,
        uint time
    ) external onlyTransport {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        l.chainTotalValues[siblingChainId] = VaultParentStorage.ChainValue({
            value: value,
            lastUpdate: time
        });
    }
}


// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { VaultBaseInternal } from "./VaultBaseInternal.sol";
import { VaultOwnership } from "./VaultOwnership.sol";
import { Registry } from "./Registry.sol";
import { VaultParentStorage } from "./VaultParentStorage.sol";
import { IVaultParentManager } from "./IVaultParentManager.sol";

import { Constants } from "./Constants.sol";

import "./console.sol";

contract VaultParentInternal is VaultOwnership, VaultBaseInternal {
    modifier noBridgeInProgress() {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        require(!l.bridgeInProgress, 'bridge in progress');
        _;
    }

    modifier noWithdrawInProgress() {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        require(l.withdrawsInProgress == 0, 'withdraw in progress');
        _;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        // If minting just return
        if (from == address(0)) {
            return;
        }
        if (tokenId == _MANAGER_TOKEN_ID) {
            require(to == _manager(), 'must use changeManager');
        }
    }

    function _getSendQuote(
        bytes4 sigHash,
        uint16 chainId
    ) internal view returns (uint fee) {
        if (sigHash == IVaultParentManager.requestBridgeToChain.selector) {
            fee = bridgeQuote(chainId);
        } else {
            fee = _registry().transport().getSendQuote(chainId);
        }
    }

    function _getSendQuoteMultiChain(
        bytes4 sigHash,
        uint16[] memory chainIds
    ) internal view returns (uint[] memory fees, uint256 totalSendFee) {
        fees = new uint[](chainIds.length);
        for (uint i = 0; i < chainIds.length; i++) {
            fees[i] = _getSendQuote(sigHash, chainIds[i]);
            totalSendFee += fees[i];
        }
    }

    function bridgeQuote(uint16 dstChainId) internal view returns (uint fee) {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        // check minAmountOut is within threshold
        address dstVault = l.children[dstChainId];
        require(dstVault != address(0), 'no dst vault');

        (fee, ) = _registry().transport().getBridgeAssetQuote(
            dstChainId,
            dstVault,
            _registry().chainId(),
            address(this)
        );
    }

    function _getVaultValue() internal view returns (uint value) {
        value = _registry().accountant().getVaultValue(address(this));
    }

    function _totalValueAcrossAllChains() internal view returns (uint value) {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        value += _getVaultValue();
        for (uint8 i = 0; i < l.childChains.length; i++) {
            require(
                _isNotStale(l.chainTotalValues[l.childChains[i]].lastUpdate),
                'stale'
            );
            value += l.chainTotalValues[l.childChains[i]].value;
        }
    }

    function _unitPrice() internal view returns (uint price) {
        price =
            (_totalValueAcrossAllChains() * Constants.VAULT_PRECISION) /
            _totalShares();
    }

    function _childChains(uint index) internal view returns (uint16 chainId) {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        return l.childChains[index];
    }

    function _children(uint16 chainId) internal view returns (address) {
        return VaultParentStorage.layout().children[chainId];
    }

    function inSync() internal view returns (bool) {
        VaultParentStorage.Layout storage l = VaultParentStorage.layout();

        for (uint8 i = 0; i < l.childChains.length; i++) {
            if (_isNotStale(l.chainTotalValues[l.childChains[i]].lastUpdate)) {
                continue;
            } else {
                return false;
            }
        }
        return true;
    }

    function _isNotStale(uint lastUpdate) internal view returns (bool) {
        return lastUpdate > block.timestamp - _registry().livelinessThreshold();
    }
}


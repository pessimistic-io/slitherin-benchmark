// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IForwarderRegistry} from "./IForwarderRegistry.sol";
import {ERC20Storage} from "./ERC20Storage.sol";
import {ERC20DetailedStorage} from "./ERC20DetailedStorage.sol";
import {ERC20MetadataStorage} from "./ERC20MetadataStorage.sol";
import {ERC20PermitStorage} from "./ERC20PermitStorage.sol";
import {ContractOwnershipStorage} from "./ContractOwnershipStorage.sol";
import {ERC20Base} from "./ERC20Base.sol";
import {ERC20DetailedBase} from "./ERC20DetailedBase.sol";
import {ERC20MetadataBase} from "./ERC20MetadataBase.sol";
import {ERC20PermitBase} from "./ERC20PermitBase.sol";
import {ERC20SafeTransfersBase} from "./ERC20SafeTransfersBase.sol";
import {ERC20BatchTransfersBase} from "./ERC20BatchTransfersBase.sol";
import {ERC20MintableBase} from "./ERC20MintableBase.sol";
import {ERC20BurnableBase} from "./ERC20BurnableBase.sol";
import {TokenRecoveryBase} from "./TokenRecoveryBase.sol";
import {ContractOwnershipBase} from "./ContractOwnershipBase.sol";
import {AccessControlBase} from "./AccessControlBase.sol";
import {InterfaceDetection} from "./InterfaceDetection.sol";
import {Context} from "./Context.sol";
import {ForwarderRegistryContextBase} from "./ForwarderRegistryContextBase.sol";
import {ForwarderRegistryContext} from "./ForwarderRegistryContext.sol";

/// @title ERC20 Fungible Token Standard, mintable and burnable preset contract (proxied version).
contract ERC20MintBurnProxied is
    ERC20Base,
    ERC20DetailedBase,
    ERC20PermitBase,
    ERC20MetadataBase,
    ERC20SafeTransfersBase,
    ERC20BatchTransfersBase,
    ERC20MintableBase,
    ERC20BurnableBase,
    AccessControlBase,
    InterfaceDetection,
    TokenRecoveryBase,
    ContractOwnershipBase,
    ForwarderRegistryContext
{
    using ERC20DetailedStorage for ERC20DetailedStorage.Layout;
    using ContractOwnershipStorage for ContractOwnershipStorage.Layout;

    constructor(IForwarderRegistry forwarderRegistry) ForwarderRegistryContext(forwarderRegistry) {}

    function init(string calldata tokenName, string calldata tokenSymbol, uint8 tokenDecimals) external {
        ContractOwnershipStorage.layout().proxyInit(_msgSender());
        ERC20Storage.init();
        ERC20Storage.initERC20BatchTransfers();
        ERC20Storage.initERC20SafeTransfers();
        ERC20Storage.initERC20Mintable();
        ERC20Storage.initERC20Burnable();
        ERC20DetailedStorage.layout().proxyInit(tokenName, tokenSymbol, tokenDecimals);
        ERC20MetadataStorage.init();
        ERC20PermitStorage.init();
    }

    /// @inheritdoc ForwarderRegistryContextBase
    function _msgSender() internal view virtual override(Context, ForwarderRegistryContextBase) returns (address) {
        return ForwarderRegistryContextBase._msgSender();
    }

    /// @inheritdoc ForwarderRegistryContextBase
    function _msgData() internal view virtual override(Context, ForwarderRegistryContextBase) returns (bytes calldata) {
        return ForwarderRegistryContextBase._msgData();
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IForwarderRegistry} from "./IForwarderRegistry.sol";
import {ERC20Storage} from "./ERC20Storage.sol";
import {ProxyAdminStorage} from "./ProxyAdminStorage.sol";
import {ERC20MintableBase} from "./ERC20MintableBase.sol";
import {Context} from "./Context.sol";
import {ForwarderRegistryContextBase} from "./ForwarderRegistryContextBase.sol";

/// @title ERC20 Fungible Token Standard, optional extension: Mintable (facet version).
/// @dev This contract is to be used as a diamond facet (see ERC2535 Diamond Standard https://eips.ethereum.org/EIPS/eip-2535).
/// @dev Note: This facet depends on {ProxyAdminFacet}, {ContractOwnershipFacet}, {InterfaceDetectionFacet} and {AccessControlFacet}.
contract ERC20MintableFacet is ERC20MintableBase, ForwarderRegistryContextBase {
    using ProxyAdminStorage for ProxyAdminStorage.Layout;

    constructor(IForwarderRegistry forwarderRegistry) ForwarderRegistryContextBase(forwarderRegistry) {}

    /// @notice Marks the following ERC165 interface(s) as supported: ERC20Mintable.
    /// @dev Reverts if the sender is not the proxy admin.
    function initERC20MintableStorage() external {
        ProxyAdminStorage.layout().enforceIsProxyAdmin(_msgSender());
        ERC20Storage.initERC20Mintable();
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


// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IForwarderRegistry} from "./IForwarderRegistry.sol";
import {ERC1155Storage} from "./ERC1155Storage.sol";
import {ProxyAdminStorage} from "./ProxyAdminStorage.sol";
import {ERC1155DeliverableBase} from "./ERC1155DeliverableBase.sol";
import {Context} from "./Context.sol";
import {ForwarderRegistryContextBase} from "./ForwarderRegistryContextBase.sol";

/// @title ERC1155 Multi Token Standard, optional extension: Deliverable (facet version).
/// @dev This contract is to be used as a diamond facet (see ERC2535 Diamond Standard https://eips.ethereum.org/EIPS/eip-2535).
/// @dev Note: This facet depends on {ProxyAdminFacet}, and {InterfaceDetectionFacet}.
contract ERC1155DeliverableFacet is ERC1155DeliverableBase, ForwarderRegistryContextBase {
    using ProxyAdminStorage for ProxyAdminStorage.Layout;

    constructor(IForwarderRegistry forwarderRegistry) ForwarderRegistryContextBase(forwarderRegistry) {}

    /// @notice Marks the following ERC165 interfaces as supported: ERC1155Deliverable.
    /// @dev Reverts if the sender is not the proxy admin.
    function initERC1155DeliverableStorage() external {
        ProxyAdminStorage.layout().enforceIsProxyAdmin(_msgSender());
        ERC1155Storage.initERC1155Deliverable();
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


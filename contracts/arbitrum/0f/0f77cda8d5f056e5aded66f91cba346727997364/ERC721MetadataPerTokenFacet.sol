// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IForwarderRegistry} from "./IForwarderRegistry.sol";
import {ERC721ContractMetadataStorage} from "./ERC721ContractMetadataStorage.sol";
import {ProxyAdminStorage} from "./ProxyAdminStorage.sol";
import {ERC721MetadataPerTokenBase} from "./ERC721MetadataPerTokenBase.sol";
import {Context} from "./Context.sol";
import {ForwarderRegistryContextBase} from "./ForwarderRegistryContextBase.sol";

/// @title ERC721 Non-Fungible Token Standard, optional extension: Metadata (facet version).
/// @notice ERC721Metadata implementation where tokenURIs are set individually per token.
/// @dev This contract is to be used as a diamond facet (see ERC2535 Diamond Standard https://eips.ethereum.org/EIPS/eip-2535).
/// @dev Note: This facet depends on {ProxyAdminFacet}, {ContractOwnershipFacet} and {InterfaceDetectionFacet}.
contract ERC721MetadataPerTokenFacet is ERC721MetadataPerTokenBase, ForwarderRegistryContextBase {
    using ProxyAdminStorage for ProxyAdminStorage.Layout;
    using ERC721ContractMetadataStorage for ERC721ContractMetadataStorage.Layout;

    constructor(IForwarderRegistry forwarderRegistry) ForwarderRegistryContextBase(forwarderRegistry) {}

    /// @notice Initializes the storage with a name and symbol.
    /// @notice Sets the proxy initialization phase to `1`.
    /// @notice Marks the following ERC165 interface(s) as supported: ERC721Metadata.
    /// @dev Note: This function should be called ONLY in the init function of a proxied contract.
    /// @dev Reverts if the sender is not the proxy admin.
    /// @dev Reverts if the proxy initialization phase is set to `1` or above.
    /// @param tokenName The token name.
    /// @param tokenSymbol The token symbol.
    function initERC721MetadataStorage(string calldata tokenName, string calldata tokenSymbol) external {
        ProxyAdminStorage.layout().enforceIsProxyAdmin(_msgSender());
        ERC721ContractMetadataStorage.layout().proxyInit(tokenName, tokenSymbol);
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


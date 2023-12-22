// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IForwarderRegistry} from "./IForwarderRegistry.sol";
import {ERC20Storage} from "./ERC20Storage.sol";
import {ProxyAdminStorage} from "./ProxyAdminStorage.sol";
import {ERC20Base} from "./ERC20Base.sol";
import {Context} from "./Context.sol";
import {ForwarderRegistryContextBase} from "./ForwarderRegistryContextBase.sol";

/// @title ERC20 Fungible Token Standard (facet version).
/// @dev This contract is to be used as a diamond facet (see ERC2535 Diamond Standard https://eips.ethereum.org/EIPS/eip-2535).
/// @dev Note: This facet depends on {ProxyAdminFacet} and {InterfaceDetectionFacet}.
contract ERC20Facet is ERC20Base, ForwarderRegistryContextBase {
    using ERC20Storage for ERC20Storage.Layout;
    using ProxyAdminStorage for ProxyAdminStorage.Layout;

    constructor(IForwarderRegistry forwarderRegistry) ForwarderRegistryContextBase(forwarderRegistry) {}

    /// @notice Marks the following ERC165 interface(s) as supported: ERC20, ERC20Allowance.
    /// @dev Reverts if the sender is not the proxy admin.
    function initERC20Storage() external {
        ProxyAdminStorage.layout().enforceIsProxyAdmin(_msgSender());
        ERC20Storage.init();
    }

    /// @notice Marks the following ERC165 interface(s) as supported: ERC20, ERC20Allowance.
    /// @dev Reverts if the sender is not the proxy admin.
    function initERC20StorageWithAllocations(address[] calldata initialHolders, uint256[] calldata initialAllocations) external {
        ProxyAdminStorage.layout().enforceIsProxyAdmin(_msgSender());
        ERC20Storage.initWithAllocations(initialHolders, initialAllocations);
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


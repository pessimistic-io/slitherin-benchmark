pragma solidity >=0.8.19;

import "./InitError.sol";
import "./OwnableStorage.sol";
import "./UUPSProxyWithOwner.sol";
import "./IUUPSImplementation.sol";
import "./IBaseAssociatedSystemsModule.sol";
import "./INftModule.sol";
import "./AssociatedSystem.sol";
/**
 * @title Module for connecting a system with other associated systems.
 * @dev See IBaseAssociatedSystemsModule.
 */

contract BaseAssociatedSystemsModule is IBaseAssociatedSystemsModule {
    using AssociatedSystem for AssociatedSystem.Data;

    /**
     * @inheritdoc IBaseAssociatedSystemsModule
     */
    function initOrUpgradeNft(bytes32 id, string memory name, string memory symbol, string memory uri, address impl)
        external
        override
    {
        OwnableStorage.onlyOwner();
        _initOrUpgradeNft(id, name, symbol, uri, impl);
    }

    /**
     * @inheritdoc IBaseAssociatedSystemsModule
     */
    function getAssociatedSystem(bytes32 id) external view override returns (address addr, bytes32 kind) {
        addr = AssociatedSystem.load(id).proxy;
        kind = AssociatedSystem.load(id).kind;
    }

    modifier onlyIfAssociated(bytes32 id) {
        if (address(AssociatedSystem.load(id).proxy) == address(0)) {
            revert MissingAssociatedSystem(id);
        }

        _;
    }

    function _setAssociatedSystem(bytes32 id, bytes32 kind, address proxy, address impl) internal {
        AssociatedSystem.load(id).set(proxy, impl, kind);
        emit AssociatedSystemSet(kind, id, proxy, impl);
    }

    function _upgradeNft(bytes32 id, address impl) internal {
        AssociatedSystem.Data storage store = AssociatedSystem.load(id);
        store.expectKind(AssociatedSystem.KIND_ERC721);

        store.impl = impl;

        address proxy = store.proxy;

        // tell the associated proxy to upgrade to the new implementation
        IUUPSImplementation(proxy).upgradeTo(impl);

        _setAssociatedSystem(id, AssociatedSystem.KIND_ERC721, proxy, impl);
    }

    function _initOrUpgradeNft(bytes32 id, string memory name, string memory symbol, string memory uri, address impl)
        internal
    {
        OwnableStorage.onlyOwner();
        AssociatedSystem.Data storage store = AssociatedSystem.load(id);

        if (store.proxy != address(0)) {
            _upgradeNft(id, impl);
        } else {
            // create a new proxy and own it
            address proxy = address(new UUPSProxyWithOwner(impl, address(this)));

            INftModule(proxy).initialize(name, symbol, uri);

            _setAssociatedSystem(id, AssociatedSystem.KIND_ERC721, proxy, impl);
        }
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeOwnable.sol";
import "./OwnableStorage.sol";
import "./ERC165Storage.sol";
import "./IERC165.sol";
import "./UpgradeableProxyOwnable.sol";
import "./UpgradeableProxyStorage.sol";

import "./IVault.sol";

import "./QueueStorage.sol";

/**
 * @title Knox Queue Proxy Contract
 * @dev contracts are upgradable
 */

contract QueueProxy is SafeOwnable, UpgradeableProxyOwnable {
    using ERC165Storage for ERC165Storage.Layout;
    using OwnableStorage for OwnableStorage.Layout;
    using QueueStorage for QueueStorage.Layout;
    using UpgradeableProxyStorage for UpgradeableProxyStorage.Layout;

    constructor(
        uint256 maxTVL,
        address exchange,
        address implementation
    ) {
        {
            QueueStorage.Layout storage l = QueueStorage.layout();
            l.Exchange = IExchangeHelper(exchange);
            l.maxTVL = maxTVL;
        }

        {
            ERC165Storage.Layout storage l = ERC165Storage.layout();
            l.setSupportedInterface(type(IERC165).interfaceId, true);
            l.setSupportedInterface(type(IERC1155).interfaceId, true);
        }

        OwnableStorage.layout().setOwner(msg.sender);
        UpgradeableProxyStorage.layout().setImplementation(implementation);
    }

    receive() external payable {}

    function _transferOwnership(address account)
        internal
        virtual
        override(OwnableInternal, SafeOwnable)
    {
        super._transferOwnership(account);
    }

    /**
     * @notice get address of implementation contract
     * @return implementation address
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeOwnable.sol";
import "./OwnableStorage.sol";
import "./UpgradeableProxyOwnable.sol";
import "./UpgradeableProxyStorage.sol";

import "./AuctionStorage.sol";

/**
 * @title Knox Auction Proxy Contract
 * @dev contracts are upgradable
 */

contract AuctionProxy is SafeOwnable, UpgradeableProxyOwnable {
    using AuctionStorage for AuctionStorage.Layout;
    using OwnableStorage for OwnableStorage.Layout;
    using UpgradeableProxyStorage for UpgradeableProxyStorage.Layout;

    constructor(
        int128 deltaOffset64x64,
        uint256 minSize,
        address exchange,
        address pricer,
        address implementation
    ) {
        AuctionStorage.Layout storage l = AuctionStorage.layout();

        l.deltaOffset64x64 = deltaOffset64x64;
        l.minSize = minSize;
        l.Exchange = IExchangeHelper(exchange);
        l.Pricer = IPricer(pricer);

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


// SPDX-License-Identifier: Apache 2.0

pragma solidity ^0.8;

import "./Clones.sol";
import "./Ownable.sol";
import "./AspenPaymentSplitter.sol";
import "./IAspenDeployer.sol";

contract AspenPaymentSplitterFactory is Ownable, IAspenPaymentSplitterEventsV0, ICedarImplementationVersionedV0 {
    AspenPaymentSplitter public implementation;

    struct EventParams {
        address contractAddress;
        uint256 majorVersion;
        uint256 minorVersion;
        uint256 patchVersion;
        address[] payees;
        uint256[] shares;
    }

    constructor() {
        // Deploy the implementation contract and set implementationAddress
        implementation = new AspenPaymentSplitter();
        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        implementation.initialize(recipients, shares);

        (uint256 major, uint256 minor, uint256 patch) = implementation.implementationVersion();
        emit AspenImplementationDeployed(address(implementation), major, minor, patch, "AspenPaymentSplitter");
    }

    function emitEvent(EventParams memory params) private {
        emit AspenPaymentSplitterDeployment(
            params.contractAddress,
            params.majorVersion,
            params.minorVersion,
            params.patchVersion,
            params.payees,
            params.shares
        );
    }

    function deploy(address[] memory payees, uint256[] memory shares_)
        external
        onlyOwner
        returns (AspenPaymentSplitter)
    {
        // newClone = PaymentSplitter(Clones.clone(address((implementation)));
        AspenPaymentSplitter newClone = new AspenPaymentSplitter();
        newClone.initialize(payees, shares_);

        (uint256 major, uint256 minor, uint256 patch) = newClone.implementationVersion();

        EventParams memory params;
        params.contractAddress = address(newClone);
        params.majorVersion = major;
        params.minorVersion = minor;
        params.patchVersion = patch;
        params.payees = payees;
        params.shares = shares_;

        emitEvent(params);
        return newClone;
    }

    function implementationVersion()
        external
        view
        override
        returns (
            uint256 major,
            uint256 minor,
            uint256 patch
        )
    {
        return implementation.implementationVersion();
    }
}


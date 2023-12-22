// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.16;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract VoidDexV4 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /*
    ==============================================================================

    █▀▀ █▀█ █▄░█ █▀▀ █ █▀▀ █░█ █▀█ ▄▀█ ▀█▀ █ █▀█ █▄░█ █▀
    █▄▄ █▄█ █░▀█ █▀░ █ █▄█ █▄█ █▀▄ █▀█ ░█░ █ █▄█ █░▀█ ▄█

    ==============================================================================
    */
    constructor() initializer {}

    function initialize(address _ownerAddress) public initializer {
        __Ownable_init();
        transferOwnership(_ownerAddress);
        __UUPSUpgradeable_init();
    }

    // function setOwner(address _ownerAddress) public {
    //     __Ownable_init();
    //     transferOwnership(_ownerAddress);
    //     __UUPSUpgradeable_init();
    // }

    fallback() external payable {}

    /***
     * Due to the way proxy is implemented.
     * This receive() function will never be called at all.
     * The receive() will stop at the Proxy contract, not being delegated to this one.
     * All in the spirit of fixing the interaction between WETH wrap/unwrap and this contract.
     */
    receive() external payable {}

    function _authorizeUpgrade(address) internal override onlyOwner {}
}


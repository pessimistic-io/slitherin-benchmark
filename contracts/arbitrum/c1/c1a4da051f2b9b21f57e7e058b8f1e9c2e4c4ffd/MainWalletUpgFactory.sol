// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./MainWalletUpg.sol";
import "./MainWalletBeacon.sol";
import "./BeaconProxy.sol";

contract MainWalletUpgFactory {

    MainWalletBeacon immutable beacon;

    constructor(address _initBlueprint) {
        beacon = new MainWalletBeacon(_initBlueprint);
    }

    function createMainWallet(string memory _companyName, bool _isPrivate, address _developerAddress) public returns(address){
        BeaconProxy ship = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(MainWalletUpg(address(0)).initialize.selector, _companyName, _isPrivate, _developerAddress)
        );
        return address(ship);
    }

    function getBeacon() public view returns (address) {
        return address(beacon);
    }

    function getImplementation() public view returns (address) {
        return beacon.implementation();
    }

}


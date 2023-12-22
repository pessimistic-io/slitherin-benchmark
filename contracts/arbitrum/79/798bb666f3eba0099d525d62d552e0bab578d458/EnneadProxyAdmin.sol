// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

interface IEnneadProxy {
    function getImplementation() external view returns (address);
    function changeAdmin(address newAdmin) external;
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
    function proxyAdmin() external view returns (address);
}

interface IUpgradeableBeacon {
    function implementation() external view returns (address);
    function transferOwnership(address newOwner) external;
    function owner() external view returns (address);
}

contract EnneadV2ProxyAdmin is Ownable {

    function getProxyImplementation(address proxy) public view returns (address) {
        return IEnneadProxy(proxy).getImplementation();
    }

    function upgrade(address proxy, address implementation) public onlyOwner {
        IEnneadProxy(proxy).upgradeTo(implementation);
    }

    function upgradeAndCall(address proxy, address implementation, bytes memory data) public onlyOwner {
        IEnneadProxy(proxy).upgradeToAndCall(implementation, data);
    }

    function getProxyAdmin(address proxy) public view returns (address) {
        return IEnneadProxy(proxy).proxyAdmin();
    }

    function changeProxyAdmin(address proxy, address newAdmin) public onlyOwner {
        IEnneadProxy(proxy).changeAdmin(newAdmin);
    }

    function getBeaconImplementation(address proxy) public view returns (address) {
        return IUpgradeableBeacon(proxy).implementation();
    }

    function changeBeaconAdmin(address proxy, address newAdmin) public onlyOwner {
        IUpgradeableBeacon(proxy).transferOwnership(newAdmin);
    }

    function getBeaconAdmin(address proxy) public view returns (address) {
        return IUpgradeableBeacon(proxy).owner();
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./EnumerableSetUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./UpgradeableBeacon.sol";
import "./BeaconProxy.sol";
import "./AdminControl.sol";

contract PayableBeaconFactory is AdminControl {

    event NewDefaultAdmin(address indexed newDefaultAdmin);
    event NewConcreteImplementation(bytes32 indexed productType, address implementation);
    event NewDelegateImplementation(bytes32 indexed productType, address implementation);
    event NewConcreteBeacon(bytes32 indexed productType, address beacon, address implementation);
    event NewDelegateBeacon(bytes32 indexed productType, address beacon, address implementation);
    event UpgradeConcreteBeacon(bytes32 indexed productType, address indexed beacon, address newImplementation);
    event UpgradeDelegateBeacon(bytes32 indexed productType, address indexed beacon, address newImplementation);
    event TransferBeaconOwnership(bytes32 indexed productType, address newOwner);
    event NewConcreteBeaconProxy(bytes32 indexed productType, bytes32 indexed productName, address beaconProxy);
    event NewDelegateBeaconProxy(bytes32 indexed productType, bytes32 indexed productName, address beaconProxy);
    event RemoveConcreteBeaconProxy(bytes32 indexed productType, bytes32 indexed productName);
    event RemoveDelegateBeaconProxy(bytes32 indexed productType, bytes32 indexed productName);
    event SetManager(address indexed manager, bool enabled);

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    EnumerableSetUpgradeable.AddressSet internal _managers;

    address private _self;

    address public defaultAdmin;

    struct PayableAddressPair {
        address payableDelegate;
        address payableConcrete;
    }

    struct ProductType {
        PayableAddressPair implementations;
        PayableAddressPair beacons;
        mapping(bytes32 => PayableAddressPair) proxies;
    }

    mapping(bytes32 => ProductType) public productTypes;

    modifier onlyManagers() {
        require(_msgSender() == admin || _managers.contains(_msgSender()));
        _;
    }

    function initialize() external initializer {
        __AdminControl_init(_msgSender());
        _self = address(this);
        _setDefaultAdmin(_msgSender());
    }

    function setConcreteImplementation(string memory productType_, address implementation_) public virtual onlyAdmin {
        bytes32 productTypeHash = getHash(productType_);
        productTypes[productTypeHash].implementations.payableConcrete = implementation_;
        emit NewConcreteImplementation(productTypeHash, implementation_);
    }

    function setDelegateImplementation(string memory productType_, address implementation_) public virtual onlyAdmin {
        bytes32 productTypeHash = getHash(productType_);
        productTypes[productTypeHash].implementations.payableDelegate = implementation_;
        emit NewDelegateImplementation(productTypeHash, implementation_);
    }

    function deployConcreteBeacon(string memory productType_) public virtual onlyAdmin returns (address beaconAddress) {
        bytes32 productTypeHash = getHash(productType_);
        address implementation = productTypes[productTypeHash].implementations.payableConcrete;
        require(implementation != address(0), "implementation not deployed");
        require(productTypes[productTypeHash].beacons.payableConcrete == address(0), "beacon already deployed");

        beaconAddress = address(new UpgradeableBeacon(implementation));
        productTypes[productTypeHash].beacons.payableConcrete = beaconAddress;
        emit NewConcreteBeacon(productTypeHash, beaconAddress, implementation);
    }

    function deployDelegateBeacon(string memory productType_) public virtual onlyAdmin returns (address beaconAddress) {
        bytes32 productTypeHash = getHash(productType_);
        address implementation = productTypes[productTypeHash].implementations.payableDelegate;
        require(implementation != address(0), "implementation not deployed");
        require(productTypes[productTypeHash].beacons.payableDelegate == address(0), "beacon already deployed");

        beaconAddress = address(new UpgradeableBeacon(implementation));
        productTypes[productTypeHash].beacons.payableDelegate = beaconAddress;
        emit NewDelegateBeacon(productTypeHash, beaconAddress, implementation);
    }

    function setConcreteBeacon(string memory productType_, address beacon_) public virtual onlyAdmin {
        bytes32 productTypeHash = getHash(productType_);
        productTypes[productTypeHash].beacons.payableConcrete = beacon_;
        emit NewConcreteBeacon(productTypeHash, beacon_, UpgradeableBeacon(beacon_).implementation());
    }

    function setDelegateBeacon(string memory productType_, address beacon_) public virtual onlyAdmin {
        bytes32 productTypeHash = getHash(productType_);
        productTypes[productTypeHash].beacons.payableDelegate = beacon_;
        emit NewDelegateBeacon(productTypeHash, beacon_, UpgradeableBeacon(beacon_).implementation());
    }

    function upgradeConcreteBeacon(string memory productType_) public virtual onlyAdmin {
        bytes32 productTypeHash = getHash(productType_);
        address implementation = productTypes[productTypeHash].implementations.payableConcrete;
        address beacon = productTypes[productTypeHash].beacons.payableConcrete;

        require(implementation != address(0), "implementation not deployed");
        require(UpgradeableBeacon(beacon).implementation() != implementation, "same concrete implementation");
        UpgradeableBeacon(beacon).upgradeTo(implementation);
        emit UpgradeConcreteBeacon(productTypeHash, beacon, implementation);
    }

    function upgradeDelegateBeacon(string memory productType_) public virtual onlyAdmin {
        bytes32 productTypeHash = getHash(productType_);
        address implementation = productTypes[productTypeHash].implementations.payableDelegate;
        address beacon = productTypes[productTypeHash].beacons.payableDelegate;

        require(implementation != address(0), "implementation not deployed");
        require(UpgradeableBeacon(beacon).implementation() != implementation, "same delegate implementation");
        UpgradeableBeacon(beacon).upgradeTo(implementation);
        emit UpgradeDelegateBeacon(productTypeHash, beacon, implementation);
    }

    function transferBeaconOwnership(string memory productType_, address newOwner_) public virtual onlyAdmin {
        bytes32 productTypeHash = getHash(productType_);
        UpgradeableBeacon(productTypes[productTypeHash].beacons.payableConcrete).transferOwnership(newOwner_);
        UpgradeableBeacon(productTypes[productTypeHash].beacons.payableDelegate).transferOwnership(newOwner_);
        emit TransferBeaconOwnership(productTypeHash, newOwner_);
    }

    function deployProductConcreteProxy(
        string memory productType_, string memory productName_, bytes memory data_
    ) public virtual onlyManagers returns (address proxy) {
        bytes32 productTypeHash = getHash(productType_);
        bytes32 productNameHash = getHash(productName_);
        require(productTypes[productTypeHash].proxies[productNameHash].payableConcrete == address(0), "product concrete already deployed");
        
        address beaconAddress = productTypes[productTypeHash].beacons.payableConcrete;
        proxy = _deployProductProxy(productTypeHash, productNameHash, data_, beaconAddress);
        productTypes[productTypeHash].proxies[productNameHash].payableConcrete = proxy;

        emit NewConcreteBeaconProxy(productTypeHash, productNameHash, proxy);
    }

    function deployProductDelegateProxy(
        string memory productType_, string memory productName_, bytes memory data_
    ) public virtual onlyManagers returns (address proxy) {
        bytes32 productTypeHash = getHash(productType_);
        bytes32 productNameHash = getHash(productName_);
        require(productTypes[productTypeHash].proxies[productNameHash].payableDelegate == address(0), "product delegate already deployed");
        
        address beaconAddress = productTypes[productTypeHash].beacons.payableDelegate;
        proxy = _deployProductProxy(productTypeHash, productNameHash, data_, beaconAddress);
        productTypes[productTypeHash].proxies[productNameHash].payableDelegate = proxy;

        emit NewDelegateBeaconProxy(productTypeHash, productNameHash, proxy);
    }

    function _deployProductProxy(
        bytes32 productTypeHash_, bytes32 productNameHash_, bytes memory data_, address beaconAddress_
    ) internal returns (address proxy_) {
        require(beaconAddress_ != address(0), "beacon not deployed");

        bytes32 salt = keccak256(abi.encodePacked(productTypeHash_, productNameHash_));
        proxy_ = address(new BeaconProxy{salt: salt}(beaconAddress_, new bytes(0)));

        AddressUpgradeable.functionCall(
            proxy_,
            data_,
            "initialize failed"
        );

        AddressUpgradeable.functionCall(
            proxy_,
            abi.encodeWithSelector(
                bytes4(keccak256("setPendingAdmin(address)")),
                defaultAdmin
            ),
            "set pending admin failed"
        );
    }

    function removeProductConcreteProxy(string memory productType_, string memory productName_) public virtual onlyManagers {
        bytes32 productTypeHash = getHash(productType_);
        bytes32 productNameHash = getHash(productName_);
        delete productTypes[productTypeHash].proxies[productNameHash].payableConcrete;
        emit RemoveConcreteBeaconProxy(productTypeHash, productNameHash);
    }

    function removeProductDelegateProxy(string memory productType_, string memory productName_) public virtual onlyManagers {
        bytes32 productTypeHash = getHash(productType_);
        bytes32 productNameHash = getHash(productName_);
        delete productTypes[productTypeHash].proxies[productNameHash].payableDelegate;
        emit RemoveDelegateBeaconProxy(productTypeHash, productNameHash);
    }

    function importProductConcreteProxy(string memory productType_, string memory productName_, address proxyAddress_) public virtual onlyManagers {
        bytes32 productTypeHash = getHash(productType_);
        bytes32 productNameHash = getHash(productName_);
        require(productTypes[productTypeHash].beacons.payableConcrete != address(0), "beacon not deployed");
        productTypes[productTypeHash].proxies[productNameHash].payableConcrete = proxyAddress_;
        emit NewConcreteBeaconProxy(productTypeHash, productNameHash, proxyAddress_);
    }

    function importProductDelegateProxy(string memory productType_, string memory productName_, address proxyAddress_) public virtual onlyManagers {
        bytes32 productTypeHash = getHash(productType_);
        bytes32 productNameHash = getHash(productName_);
        require(productTypes[productTypeHash].beacons.payableDelegate != address(0), "beacon not deployed");
        productTypes[productTypeHash].proxies[productNameHash].payableDelegate = proxyAddress_;
        emit NewDelegateBeaconProxy(productTypeHash, productNameHash, proxyAddress_);
    }

    function getImplementations(bytes32 productTypeHash_) public view returns (PayableAddressPair memory) {
        return productTypes[productTypeHash_].implementations;
    }

    function getBeacons(bytes32 productTypeHash_) public view returns (PayableAddressPair memory) {
        return productTypes[productTypeHash_].beacons;
    }

    function getProxies(bytes32 productTypeHash_, bytes32 productNameHash_) public view returns (PayableAddressPair memory) {
        return productTypes[productTypeHash_].proxies[productNameHash_];
    }

    function setDefaultAdmin(address newDefaultAdmin_) public virtual onlyAdmin {
        _setDefaultAdmin(newDefaultAdmin_);
    }

    function setManager(address manager_, bool enabled_) public virtual onlyAdmin {
        if (enabled_) {
            _managers.add(manager_);
        } else {
            _managers.remove(manager_);
        }
        emit SetManager(manager_, enabled_);
    }

    function _setDefaultAdmin(address newDefaultAdmin_) internal virtual {
        defaultAdmin = newDefaultAdmin_;
        emit NewDefaultAdmin(newDefaultAdmin_);
    }

    function getHash(string memory name_) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(name_));
    }
}

pragma solidity ^0.8.0;

interface IAddressAccessControl {
    function addAddress(address addr) external returns (bool);
    function addAddresses(address[] memory addresses) external;
    function removeAddress(address addr) external returns (bool);
    function contains(address addr) external view returns (bool);
    function containsAll(address[] memory addresses)external view returns (bool);
}


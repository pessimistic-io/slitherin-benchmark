// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./EnumerableSet.sol";
import "./Dev.sol";

abstract contract Caller is Dev {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private caller;

    modifier onlyCaller() {
        require(isCaller(_msgSender()), "caller is not the owner or dev");
        _;
    }

    function isCaller(address addr) public view returns (bool) {
        return caller.contains(addr);
    }

    function getCaller(uint256 index) public view returns (address) {
        require(index <= caller.length() - 1, "index out of bounds");
        return caller.at(index);
    }

    function getCallers() public view returns (address[] memory) {
        return caller.values();
    }

    function addCaller(address addr) external onlyManger returns (bool) {
        require(addr != address(0), "caller is the zero address");
        return _addCaller(addr);
    }

    function _addCaller(address addr) internal returns (bool) {
        return caller.add(addr);
    }

    function removeCaller(address addr) external onlyManger returns (bool) {
        return _removeCaller(addr);
    }

    function _removeCaller(address addr) internal returns (bool) {
        return caller.remove(addr);
    }
}


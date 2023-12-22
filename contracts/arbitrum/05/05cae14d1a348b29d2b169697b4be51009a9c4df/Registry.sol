// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;
import { Owned } from "./Owned.sol";

contract Registry is Owned {
    event Registered(string key, bytes value);

    mapping(string key => bytes value) private _registry;

    constructor(address owner_) Owned (owner_){ }

    function set(string memory key, bytes memory value) external onlyOwner {
        _registry[key] = value;
        emit Registered(key, value);
    }

    function get(string calldata key) external view returns (bytes memory) {
        return _registry[key];
    }
}


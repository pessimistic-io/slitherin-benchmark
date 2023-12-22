// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./OnlyGovernance.sol";
import "./OnlyBridge.sol";
import {Storage} from "./Struct.sol";

contract SpaceStorage is OnlyGovernance, OnlyBridge {

    uint24 public threshold;
    mapping(address => bool) public validators;

    mapping(uint256 => Storage.NETWORK) public known_networks;

    mapping(address => Storage.TKN) _minted;

    mapping(string => address) public getAddressFromOriginHash;

    mapping(bytes32 => uint256) public transfers;
    
    mapping(string => address) public lock_map;

    function addNetwork(uint256 id, uint8 decimals_) onlyGovernance external {
        require(
            !known_networks[id].valid,
            "Network exist"
        );
        known_networks[id] = Storage.NETWORK({valid:true, decimals:decimals_});
    }

    function removeNetwork(uint256 id) onlyGovernance external {
        require(
            known_networks[id].valid,
            "dosnt exist network"
        );
        delete known_networks[id];
    }

    function addValidator(address validator) onlyGovernance public {
        require(
            !validators[validator],
            "Owner exist"
        );
        validators[validator] = true;
    }
    
    function removeValidator(address validator) onlyGovernance external {
        require(
            validators[validator],
            "dosnt exist owner"
        );
        delete validators[validator];
    }
      
    function setThreshold(uint24 value) onlyGovernance external {
        threshold = value;
    }

    function addMinted(address token_address, string memory origin_hash, Storage.TKN memory tkn) onlyBridge external {
        _minted[token_address] = tkn;
        getAddressFromOriginHash[origin_hash] = token_address;
    }

    function incrementNonce(bytes32 key) onlyBridge external {
        transfers[key] += 1;
    }

    function addLockMap(string memory t, address token_hash) onlyBridge external {
        lock_map[t] = token_hash;
    }

    function minted(address key) external view returns (Storage.TKN memory){
        return _minted[key];
    }
}

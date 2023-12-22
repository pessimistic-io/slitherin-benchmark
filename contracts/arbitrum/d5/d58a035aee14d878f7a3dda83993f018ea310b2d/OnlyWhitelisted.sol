// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "./Ownable.sol";

abstract contract OnlyWhitelisted is Ownable {
    mapping(uint8 => mapping(address => bool)) public isWhitelisted;

    event WhitelistedAdded(address indexed whitelister, uint8 tier);
    event WhitelistedRemoved(address indexed whitelister, uint8 tier);

    uint8 public constant WHITELIST_DEFAULT = 0;
    uint8 public constant WHITELIST_ADMIN = 1;
    uint8 private nextId = 2;

    constructor() {
        isWhitelisted[WHITELIST_DEFAULT][_msgSender()] = true;
        isWhitelisted[WHITELIST_ADMIN][_msgSender()] = true;
    }


    function consumeNextId() internal returns (uint8) {
        require(nextId != type(uint8).max, "OnlyWhitelisted: no more ids available");
        uint8 id = nextId;
        nextId++;
        return id;
    }
    

    modifier onlyWhitelisted() {
        require(isWhitelisted[WHITELIST_DEFAULT][_msgSender()], "OnlyWhitelisted: caller is not whitelisted");
        _;
    }
    modifier onlyWhitelistedTier(uint8 _tier) {
        require(isWhitelisted[_tier][_msgSender()], "OnlyWhitelisted: caller is not whitelisted for this tier");
        _;
    }
    modifier onlyAdmin() {
        require(isWhitelisted[WHITELIST_ADMIN][_msgSender()] || _msgSender() == owner(), "OnlyWhitelisted: caller is not an admin");
        _;
    }


    function setWhitelisted(address _whitelister, bool _state) public virtual onlyAdmin {
        setWhitelisted(_whitelister, WHITELIST_DEFAULT, _state);
    }
    function setWhitelisted(address _whitelister, uint8 _tier, bool _state) public virtual onlyAdmin {
        require(isWhitelisted[_tier][_whitelister] != _state, "OnlyWhitelisted: target is already a whitelister");
        isWhitelisted[_tier][_whitelister] = _state;
        if (_state) {
            emit WhitelistedAdded(_whitelister, _tier);
        } else {
            emit WhitelistedRemoved(_whitelister, _tier);
        }
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "./Initializable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ICurrencyManager} from "./ICurrencyManager.sol";
import {CurrencyManagerStorage} from "./CurrencyManagerStorage.sol";

contract CurrencyManager is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ICurrencyManager,
    CurrencyManagerStorage
{
    function initialize() external initializer {
        __Ownable_init();
    }

    // For UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override {
        require(_msgSender() == owner(), "CM: caller is not owner");
    }

    function add(address currency) external override onlyOwner {
        require(!currencies[currency], "CM: already added");
        currencies[currency] = true;
        emit Added(currency);
    }

    function remove(address currency) external override onlyOwner {
        require(currencies[currency], "CM: not added");
        currencies[currency] = false;
        emit Removed(currency);
    }

    function isValid(address c) public view override returns (bool valid) {
        return currencies[c];
    }
}


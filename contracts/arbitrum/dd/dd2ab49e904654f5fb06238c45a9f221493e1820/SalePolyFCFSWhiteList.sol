// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SalePolyFCFS} from "./SalePolyFCFS.sol";

contract SalePolyFCFSWhiteList is SalePolyFCFS {
    struct Whitelist {
        bool isWhitelisted;
        uint256 allocatedAmount;
    }
    mapping(address => Whitelist) public whitelistInfo;

    function setWhitelist(
        address[] memory _whitelist,
        uint256[] memory _amount
    ) external onlyAdmin {
        for (uint256 i = 0; i < _whitelist.length; i++) {
            whitelistInfo[_whitelist[i]].isWhitelisted = true;
            whitelistInfo[_whitelist[i]].allocatedAmount = _amount[i];
        }
    }

    function setWhitelist(
        address _whitelist,
        uint256 _amount,
        bool _isWhitelisted
    ) external onlyAdmin {
        whitelistInfo[_whitelist].isWhitelisted = _isWhitelisted;
        whitelistInfo[_whitelist].allocatedAmount = _amount;
    }

    function deposit(uint256 _amount) public payable override {
        require(
            whitelistInfo[msg.sender].isWhitelisted,
            "SaleFCFSWhitelist: not in whitelist"
        );
        super.deposit(_amount);
    }
}


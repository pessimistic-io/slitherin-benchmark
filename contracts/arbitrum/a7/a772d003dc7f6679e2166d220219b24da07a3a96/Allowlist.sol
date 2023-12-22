// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "./Ownable.sol";

contract Allowlist is Ownable {
    bool public passed;

    mapping(address => bool) public accounts;

    event Permit(address[] indexed _account, uint256 _timestamp);
    event Forbid(address[] indexed _account, uint256 _timestamp);
    event TogglePassed(bool _currentState, uint256 _timestamp);

    constructor(bool _passed) {
        passed = _passed;
    }

    function permit(address[] calldata _accounts) public onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            require(_accounts[i] != address(0), "Allowlist: Account cannot be 0x0");

            accounts[_accounts[i]] = true;
        }

        emit Permit(_accounts, block.timestamp);
    }

    function forbid(address[] calldata _accounts) public onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            accounts[_accounts[i]] = false;
        }

        emit Forbid(_accounts, block.timestamp);
    }

    function togglePassed() public onlyOwner {
        passed = !passed;

        emit TogglePassed(passed, block.timestamp);
    }

    function can(address _account) external view returns (bool) {
        if (passed) return true;

        return accounts[_account];
    }
}


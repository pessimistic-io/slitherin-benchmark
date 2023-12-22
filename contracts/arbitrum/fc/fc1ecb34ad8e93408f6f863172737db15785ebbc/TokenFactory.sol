// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./Token.sol";
import "./ITokenFactory.sol";

import "./OwnableUpgradeable.sol";


contract TokenFactory is OwnableUpgradeable {

    mapping(address => bool) public allowanceWhitelist;
    mapping(address => bool) public transferWhitelist;

    address public manager;

    event TokenCreated(address indexed token, string name, string symbol);

    error TF_NMO();

    function initialize(
        address[] memory _initialAllowanceWhitelist,
        address[] memory _initialTransferWhitelist,
        address _manager
    ) public initializer {
        __Ownable_init();

        for (uint256 i = 0; i < _initialAllowanceWhitelist.length; i++) {
            allowanceWhitelist[_initialAllowanceWhitelist[i]] = true;
        }

        for (uint256 i = 0; i < _initialTransferWhitelist.length; i++) {
            transferWhitelist[_initialTransferWhitelist[i]] = true;
        }

        manager = _manager;
    }

    function createToken(string memory _name, string memory _symbol) public returns (address) {
        if (msg.sender != manager && msg.sender != owner()) { revert TF_NMO(); }

        address token = address(new Token(_name, _symbol));

        emit TokenCreated(token, _name, _symbol);

        return token;
    }

    function setAllowanceWhitelist(address _address, bool _flag) external onlyOwner {
        allowanceWhitelist[_address] = _flag;
    }

    function setTransferWhitelist(address _address, bool _flag) external {
        if (msg.sender != manager && msg.sender != owner()) { revert TF_NMO(); }
        transferWhitelist[_address] = _flag;
    }

    function setManager(address _manager) external onlyOwner {
        manager = _manager;
    }
}


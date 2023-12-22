// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./ITokenFactory.sol";

import "./ERC20.sol";


contract Token is ERC20 {

    ITokenFactory public factory;

    error T_NWL();
    error T_OO();
    error T_C();

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        factory = ITokenFactory(msg.sender);
    }

    function mint(
        address to,
        uint256 amount
    ) public {
        if (msg.sender != factory.owner() && msg.sender != factory.manager()) { revert T_OO(); }
        _mint(to, amount);
    }

    function burn(
        address from,
        uint256 amount
    ) public {
        if (_isContract(from)) { revert T_C(); }
        if (msg.sender != factory.owner() && msg.sender != factory.manager()) { revert T_OO(); }
        _burn(from, amount);
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        if (factory.allowanceWhitelist(spender)) {
            return type(uint256).max;
        }

        return super.allowance(owner, spender);
    }

    function _beforeTokenTransfer(address, address to, uint256) internal view override {
        if (!factory.transferWhitelist(to)) { revert T_NWL(); }
    }

    function _isContract(address _addr) private view returns (bool){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}


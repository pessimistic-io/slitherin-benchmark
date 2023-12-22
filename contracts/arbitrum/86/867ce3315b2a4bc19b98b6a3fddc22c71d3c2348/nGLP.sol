// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./MintableERC20.sol";

contract nGLP is MintableERC20 {
    bool public inPrivateTransferMode;
    mapping (address => bool) public isHandler;

    constructor() MintableERC20("Netra GMX LP", "nGLP") {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyGov {
        inPrivateTransferMode = _inPrivateTransferMode;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        if (isHandler[spender]) {
            _transfer(from, to, amount);
            return true;
        }
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _beforeTokenTransfer(address /*from*/, address /*to*/, uint256 /*amount*/) internal view override {
        if (inPrivateTransferMode) {
            require(isHandler[msg.sender], "not whitelisted");
        }
    }
}

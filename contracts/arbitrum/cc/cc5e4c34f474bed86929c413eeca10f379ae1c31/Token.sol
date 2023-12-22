// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

contract Token is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    // 使用initializer修饰符初始化合约
    function initialize() public initializer {
        // 初始化ERC20代币名称、符号和小数位数
        __ERC20_init("Digital Trust Computation", "DTC");
        // 初始化合约拥有者为合约部署者
        __Ownable_init();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) public onlyOwner {
        _burn(msg.sender, amount);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        view
        override
        onlyOwner
    {
        (newImplementation);
    }
}


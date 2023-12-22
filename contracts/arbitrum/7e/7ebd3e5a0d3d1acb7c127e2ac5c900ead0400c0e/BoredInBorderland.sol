//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Boreable.sol";
import "./Observable.sol";

contract BoredInBorderland is ERC20, Ownable, Boreable {
    Observable public observer;
    address public userManager;

    modifier onlyUserManager() {
        require(
            _msgSender() == userManager,
            "Implementations: Not UserManager"
        );
        _;
    }

    constructor() ERC20("BoredInBorderland", "BCOIN") {
        _mint(owner(), 42_000 ether);
    }

    function userBurn(
        address account,
        uint256 amount
    ) external override onlyUserManager {
        super._burn(account, amount);
    }

    function userReward(
        address account,
        uint256 amount
    ) external override onlyUserManager {
        super._mint(account, amount);
    }

    function setUserManager(address manager) external onlyOwner {
        userManager = manager;
    }

    function setObserver(address newObserver) external onlyOwner {
        observer = Observable(newObserver);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (address(observer) != address(0)) {
            observer.observe(from, to, amount);
        }
    }
}


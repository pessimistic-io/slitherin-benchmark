// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";

contract AiHQianLan is Initializable, ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable {
    mapping(address => bool) private _frozenAccounts;

    function initialize() public initializer {
        __ERC20_init("AiHQianLan", "HQL");
        __Ownable_init();
        __Pausable_init();

        _mint(address(this), 10000000000 * 10 ** decimals());
        _transfer(address(this), 0x2bd34aD6001203602EB9a02De559181E9fA7EFBe, 880000000 * 10 ** decimals());
        _transfer(address(this), 0x903BbfFc49463B20e6082DAe16d948A8ef67E280, 810000000 * 10 ** decimals());
        _transfer(address(this), 0xB7037f4B4f582dc50a64472A509DCf2bb89f02e2, 1810000000 * 10 ** decimals());

        freezeAccount(0x2bd34aD6001203602EB9a02De559181E9fA7EFBe);
        freezeAccount(0x903BbfFc49463B20e6082DAe16d948A8ef67E280);
        freezeAccount(0xB7037f4B4f582dc50a64472A509DCf2bb89f02e2);
    }

    function freezeAccount(address target) public onlyOwner {
        _frozenAccounts[target] = true;
        emit FrozenFunds(target, true);
    }

    function unfreezeAccount(address target) public onlyOwner {
        _frozenAccounts[target] = false;
        emit FrozenFunds(target, false);
    }

    function isFrozen(address target) public view returns (bool) {
        return _frozenAccounts[target];
    }

    function transfer(address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        require(!_frozenAccounts[_msgSender()] && !_frozenAccounts[recipient], "ERC20: account is frozen");
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override whenNotPaused returns (bool) {
        require(!_frozenAccounts[sender] && !_frozenAccounts[recipient], "ERC20: account is frozen");
        return super.transferFrom(sender, recipient, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    event FrozenFunds(address target, bool frozen);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Pausable.sol";
import "./Ownable.sol";

contract Avive is ERC20, ERC20Burnable, ERC20Pausable, Ownable {
    constructor(
        address initialOwner_,
        uint256 initialSupply_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) Ownable(initialOwner_) {
        _mint(initialOwner_, initialSupply_);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}


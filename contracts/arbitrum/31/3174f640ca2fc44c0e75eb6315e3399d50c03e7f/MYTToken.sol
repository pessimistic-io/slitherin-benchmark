// contracts/MYTToken.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";

contract MYTToken is ERC20, Pausable, Ownable {

    constructor(
        uint256 initialSupply,
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20(tokenName, tokenSymbol) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Disable the {transfer} functions of contract.
     *
     * Can only be called by the current owner.
     * The contract must not be paused.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Enable the {transfer} functions of contract.
     *
     * Can only be called by the current owner.
     * The contract must be paused.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), "ERC20Pausable: token transfer while paused");
    }
}


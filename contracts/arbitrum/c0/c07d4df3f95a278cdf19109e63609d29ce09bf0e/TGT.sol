// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./draft-ERC20Permit.sol";
import "./ERC20Votes.sol";

contract TGT is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes {
    constructor() ERC20("TGT", "TGT") ERC20Permit("TGT") {
        // Mint 1 million TGT to the deployer
        _mint(msg.sender, 1_000_000_000000000000000000);
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}


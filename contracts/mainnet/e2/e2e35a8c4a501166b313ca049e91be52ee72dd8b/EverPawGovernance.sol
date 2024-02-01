// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC20.sol";
import "./draft-ERC20Permit.sol";
import "./ERC20Votes.sol";
import "./AccessControl.sol";

contract EverPAWGovernance is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    constructor()
        ERC20("EverPaw Governance", "PAWGOV")
        ERC20Permit("EverPaw Governance")
    {
        _mint(msg.sender, 1_000_000_000 * 10**decimals());
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}

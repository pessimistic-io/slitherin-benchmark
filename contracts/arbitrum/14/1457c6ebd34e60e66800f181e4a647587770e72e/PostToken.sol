// SPDX-License-Identifier: BUSL-1.1
// @author post.tech
// @contact contact@post.tech
pragma solidity ^0.8.23;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Capped.sol";
import "./ERC20Permit.sol";
import "./ERC20Votes.sol";

contract PostToken is ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * (10 ** 18);

    constructor(
        address _multisigTreasury
    )
        ERC20Permit("post.tech Token")
        ERC20("post.tech Token", "POST")
        Ownable(msg.sender)
    {
        _mint(_multisigTreasury, MAX_SUPPLY);
    }

    function nonces(
        address owner
    ) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Votes, ERC20) {
        super._update(from, to, amount);
    }

    function _maxSupply() internal pure override(ERC20Votes) returns (uint256) {
        return MAX_SUPPLY;
    }
}


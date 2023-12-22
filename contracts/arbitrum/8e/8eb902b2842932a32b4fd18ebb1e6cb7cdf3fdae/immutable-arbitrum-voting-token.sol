// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Votes.sol";
import "./draft-ERC20Permit.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract ImmutableVotingToken is ERC20, ERC20Permit, ERC20Votes {
    using SafeERC20 for IERC20;
    IERC20 public originalToken;

    constructor(
        IERC20 _originalToken
    )
        ERC20("Immutable Voting Token", "IMTVOTE")
        ERC20Permit("Immutable Voting Token")
    {
        originalToken = _originalToken;
    }

    function redeemForVotingToken(uint256 amount) public {
        originalToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function redeemForOriginalToken(uint256 amount) public {
        _burn(msg.sender, amount);
        originalToken.safeTransfer(msg.sender, amount);
    }

    // Override _afterTokenTransfer to use ERC20Votes extension
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    // Override _mint to use ERC20Votes extension
    function _mint(
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    // Override _burn to use ERC20Votes extension
    function _burn(
        address account,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}


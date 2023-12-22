// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20Burnable.sol";

import "./PVERC20Votes.sol";
import "./OFTV2.sol";

/**
 * @title GG Token
 * @author Niftydude, Jack Chuma
 */
contract GG is OFTV2, ERC20Burnable, PVERC20Votes {
    uint256 _lockedTotalSupply;
    mapping(address => uint256) _lockedVotess;

    address constant INITIAL_ADMIN = 0x9980feDF494F722887dd5d7eaee55eFe354789C6;

    constructor() OFTV2("GG", "GG", 8, INITIAL_ADMIN) ERC20Permit("GG") {
        if (block.chainid == 42170) _mint(INITIAL_ADMIN, 1000000000e18);
    }

    function lockedVotesOf(address account) public view returns (uint256) {
        return _lockedVotess[account];
    }

    function transferFromMoveVotes(
        address tokenFrom,
        address tokenTo,
        address votesFrom,
        address votesTo,
        uint256 amount
    ) external onlyRole(PROTOCOL_ROLE) {
        tokenFrom == msg.sender
            ? transfer(tokenTo, amount)
            : transferFrom(tokenFrom, tokenTo, amount);

        if (votesFrom == address(0)) {
            _mintLockedVotes(votesTo, amount);
        } else if (votesTo == address(0)) {
            _burnLockedVotes(votesFrom, amount);
        } else {
            _transferLockedVotes(votesFrom, votesTo, amount);
        }
    }

    function mintLockedVotes(
        address to,
        uint256 amount
    ) external onlyRole(PROTOCOL_ROLE) {
        _mintLockedVotes(to, amount);
    }

    function burnLockedVotes(
        address from,
        uint256 amount
    ) external onlyRole(PROTOCOL_ROLE) {
        _burnLockedVotes(from, amount);
    }

    function transferLockedVotes(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(PROTOCOL_ROLE) {
        _transferLockedVotes(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, PVERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(
        address to,
        uint256 amount
    ) internal override(ERC20, PVERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(
        address account,
        uint256 amount
    ) internal override(ERC20, PVERC20Votes) {
        super._burn(account, amount);
    }

    function _delegate(address delegator, address delegatee) internal override {
        address currentDelegate = delegates(delegator);
        uint256 delegatorVotes = balanceOf(delegator) +
            lockedVotesOf(delegator);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveVotingPower(currentDelegate, delegatee, delegatorVotes);
    }

    function _mintLockedVotes(address to, uint256 amount) private {
        require(to != address(0), "ERC20: mint to the zero address");

        _lockedTotalSupply += amount;
        unchecked {
            _lockedVotess[to] += amount;
        }

        _moveVotingPower(address(0), delegates(to), amount);
    }

    function _burnLockedVotes(address from, uint256 amount) private {
        require(from != address(0), "ERC20: burn from the zero address");

        uint256 accountVotes = _lockedVotess[from];
        require(accountVotes >= amount, "ERC20: burn amount exceeds Votes");
        unchecked {
            _lockedVotess[from] = accountVotes - amount;
            _lockedTotalSupply -= amount;
        }

        _moveVotingPower(delegates(from), address(0), amount);
    }

    function _transferLockedVotes(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromVotes = _lockedVotess[from];
        require(fromVotes >= amount, "ERC20: transfer amount exceeds Votes");
        unchecked {
            _lockedVotess[from] = fromVotes - amount;
            _lockedVotess[to] += amount;
        }

        _moveVotingPower(delegates(from), delegates(to), amount);
    }
}


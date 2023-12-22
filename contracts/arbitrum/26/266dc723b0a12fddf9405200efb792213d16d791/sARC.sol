/**
 * https://arcadeum.io
 * https://arcadeum.gitbook.io/arcadeum
 * https://twitter.com/arcadeum_io
 * https://discord.gg/qBbJ2hNPf8
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./FeeToken.sol";

contract sARC is FeeToken {
    event Stake(address indexed _account, uint256 indexed _amount, uint256 indexed _timestamp);
    event Unstake(address indexed _account, uint256 indexed _amount, uint256 indexed _timestamp);

    constructor (address _USDT, address _ARC) FeeToken(_USDT, _ARC, "Staked ARC", "sARC", 0) {}

    function stake(uint256 _toStake) external nonReentrant {
        if (_toStake > underlyingToken.balanceOf(msg.sender)) {
            revert InsufficientARCBalance(_toStake, underlyingToken.balanceOf(msg.sender));
        }
        if (_toStake > underlyingToken.allowance(msg.sender, address(this))) {
            revert InsufficientARCAllowance(_toStake, underlyingToken.allowance(msg.sender, address(this)));
        }
        underlyingToken.transferFrom(msg.sender, address(this), _toStake);
        _mint(msg.sender, _toStake);
        emit Stake(msg.sender, _toStake, block.timestamp);
    }

    function unstake(uint256 _toUnstake) external nonReentrant {
        if (_toUnstake > _balances[msg.sender]) {
            revert InsufficientsARCBalance(_toUnstake, _balances[msg.sender]);
        }
        if (_toUnstake > _allowances[msg.sender][address(this)]) {
            revert InsufficientsARCAllowance(_toUnstake, _allowances[msg.sender][address(this)]);
        }
        // ! _transferFrom(msg.sender, address(this), _toUnstake);
        _burn(msg.sender, _toUnstake);
        underlyingToken.transfer(msg.sender, _toUnstake);
        emit Unstake(msg.sender, _toUnstake, block.timestamp);
    }
}


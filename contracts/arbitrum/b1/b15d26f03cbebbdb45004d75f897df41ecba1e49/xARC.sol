/**
 * https://arcadeum.io
 * https://arcadeum.gitbook.io/arcadeum
 * https://twitter.com/arcadeum_io
 * https://discord.gg/qBbJ2hNPf8
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./FeeToken.sol";

contract xARC is FeeToken {
    event Stake(address indexed _account, uint256 indexed _amount, uint256 indexed _timestamp);

    constructor (address _USDT, address _ARC) FeeToken(_USDT, _ARC, "Burnt ARC", "xARC", 0) {}

    function stake(uint256 _toStake) external nonReentrant {
        if (_toStake > underlyingToken.balanceOf(msg.sender)) {
            revert InsufficientARCBalance(_toStake, underlyingToken.balanceOf(msg.sender));
        }
        if (_toStake > underlyingToken.allowance(msg.sender, address(this))) {
            revert InsufficientARCAllowance(_toStake, underlyingToken.allowance(msg.sender, address(this)));
        }
        underlyingToken.burnFrom(msg.sender, _toStake);
        _mint(msg.sender, _toStake);
        emit Stake(msg.sender, _toStake, block.timestamp);
    }
}


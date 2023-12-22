// SPDX-License-Identifier: MIT
// Copyright (c) 2021 Coinbase, Inc.

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./Pausable.sol";
import "./Blacklistable.sol";
import "./StandardArbERC20.sol";
import "./ERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";

contract ArbFiatToken is StandardArbERC20, Ownable, Pausable, Blacklistable {
    function initialize(
        address _gatewayAddress,
        address _l1Address,
        address owner,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external {
        gatewayAddress = _gatewayAddress;
        l1Address = _l1Address;

        _changeOwner(owner);
        super.initialize(name, symbol, decimals);
    }

    function bridgeMint(
        address account,
        uint256 amount
    ) public override onlyGateway whenNotPaused notBlacklisted(account) {
        super.bridgeMint(account, amount);
    }

    function bridgeBurn(
        address account,
        uint256 amount
    ) public override onlyGateway whenNotPaused notBlacklisted(account) {
        super.bridgeBurn(account, amount);
    }

    function approve(
        address spender,
        uint256 amount
    )
        public
        override(ERC20Upgradeable, IERC20Upgradeable)
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        return super.approve(spender, amount);
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    )
        public
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        return super.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    )
        public
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        return super.decreaseAllowance(spender, subtractedValue);
    }

    function transfer(
        address recipient,
        uint256 amount
    )
        public
        override(ERC20Upgradeable, IERC20Upgradeable)
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(recipient)
        returns (bool)
    {
        return super.transfer(recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        override(ERC20Upgradeable, IERC20Upgradeable)
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(sender)
        notBlacklisted(recipient)
        returns (bool)
    {
        return super.transferFrom(sender, recipient, amount);
    }

    function transferAndCall(
        address to,
        uint256 value,
        bytes memory data
    )
        public
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool success)
    {
        return super.transferAndCall(to, value, data);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(owner)
        notBlacklisted(spender)
    {
        super.permit(owner, spender, value, deadline, v, r, s);
    }
}


/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DeDeLend
 * Copyright (C) 2022 DeDeLend
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

pragma solidity 0.8.6;

import "./ERC20.sol";
import "./Ownable.sol";

contract PoolDDL is Ownable, ERC20("Writing DDL", "DDL") {
    uint256 public constant INITIAL_RATE = 1e18;
    uint256 public maxDepositAmount = type(uint256).max;
    mapping(address => bool) public ddlContracts;
    IERC20 public token;
    uint256 public totalLocked;
    bool public openDeDeLend = true;

    event Provide(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function changeOpenDeDeLend(bool value) external onlyOwner {
        openDeDeLend = value;
    }

    function addTotalLocked(uint256 value) public {
        require(ddlContracts[msg.sender]);
        totalLocked += value;
    }

    function subTotalLocked(uint256 value) public {
        require(ddlContracts[msg.sender]);
        totalLocked -= value;
    }

    function getTotalBalance() public view returns (uint256 balance) {
        balance = token.balanceOf(address(this));
    }

    function shareOf(address account) external view returns (uint256 share) {
        if (totalSupply() > 0)
            share = (getTotalBalance() * balanceOf(account)) / totalSupply();
        else share = 0;
    }

    constructor(
        IERC20 _token,
        address ddlContract1,
        address ddlContract2,
        address ddlContract3
    ) {
        token = _token;
        ddlContracts[ddlContract1] = true;
        ddlContracts[ddlContract2] = true;
        ddlContracts[ddlContract3] = true;
    }

    function provideFrom(
        uint256 amount,
        uint256 minShare
    ) external returns (uint256 share) {
        require(openDeDeLend, "pauseDeDeLend");
        uint256 totalBalance = getTotalBalance() + totalLocked;
        share = totalSupply() > 0 && totalBalance > 0
            ? (amount * totalSupply()) / totalBalance
            : amount * INITIAL_RATE;
        uint256 limit = maxDepositAmount - totalBalance;
        require(share >= minShare, "Pool Error: The mint limit is too large");
        require(share > 0, "Pool Error: The amount is too small");
        require(
            amount <= limit,
            "Pool Error: providing USDC is paused"
        );

        token.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, share);
        emit Provide(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        uint256 totalBalance = getTotalBalance() + totalLocked;
        require(amount <= getTotalBalance());
        uint256 burn = (amount * totalSupply()) / totalBalance;
        require(burn <= balanceOf(msg.sender), "Amount is too large");
        _burn(msg.sender, burn);
        token.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function send(address to, uint256 amount) public {
        require(ddlContracts[msg.sender]);
        require(amount <= getTotalBalance());
        token.transfer(to, amount);
    }
}


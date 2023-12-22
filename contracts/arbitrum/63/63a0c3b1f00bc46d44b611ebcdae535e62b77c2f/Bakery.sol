// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

contract Bakery {
    ERC20 public token;

    struct Staker {
        uint128 shares;
        uint128 staked;
    }

    uint256 public totalStaked;
    uint256 public totalShares;
    mapping(address => uint256) public shares;
    mapping(address => Staker) public stakers;

    event Staked(address indexed user, uint256 share, uint256 amount);
    event Withdrawn(address indexed user, uint256 share, uint256 amount);

    constructor() {
        token = ERC20(msg.sender);
    }

    function stake(uint256 amount) public {
        uint256 tokensHeld = token.balanceOf(address(this));
        uint256 _totalShares = totalShares;
        uint256 sharesToMint = amount;
        if (_totalShares != 0 && tokensHeld != 0) {
            sharesToMint = (amount * _totalShares) / tokensHeld;
        }
        totalStaked += amount;
        totalShares += sharesToMint;
        stakers[msg.sender].shares += uint128(sharesToMint);
        stakers[msg.sender].staked += uint128(amount);
        token.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, sharesToMint, amount);
    }

    function withdraw() public {
        Staker memory staker = stakers[msg.sender];
        uint256 tokenAmount = (staker.shares * token.balanceOf(address(this))) / totalShares;
        totalStaked -= staker.staked;
        totalShares -= staker.shares;
        delete stakers[msg.sender];
        token.transfer(msg.sender, tokenAmount);
        emit Withdrawn(msg.sender, staker.shares, tokenAmount);
    }
}


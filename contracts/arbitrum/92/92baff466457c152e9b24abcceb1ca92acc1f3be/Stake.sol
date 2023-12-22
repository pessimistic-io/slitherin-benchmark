// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ERC20.sol";

contract Stake is Ownable {

    ERC20 public immutable TOKEN;
    mapping(uint => mapping(string => StakeInfo)) private _ids;
    address public rewardsWallet;

    struct StakeInfo {
        address who;
        uint staked;
        uint until;
    }

    constructor(ERC20 token) {
        TOKEN = token;
        rewardsWallet = address(0x4558D5FD87ac1DE515c83224cC2b1D914bF07Fae);
    }

    function stake(uint _amount, string memory _id, uint _until, uint _type) public {
        require(_type == 0 || _type == 1, "Only type 0 and type 1 allowed");
        require(_ids[_type][_id].staked == 0, "Only one stake per token per game allowed");

        uint256 allowance = TOKEN.allowance(msg.sender, address(this));
        require(allowance >= _amount, "No enough allowance");
        TOKEN.transferFrom(msg.sender, address(this), _amount);

        _ids[_type][_id].who = msg.sender;
        _ids[_type][_id].staked = _amount;
        _ids[_type][_id].until = _until;

        emit Staked(msg.sender, _id, _amount, _type);
    }

    function stakedCheck(string memory _id, uint _type) public view returns(StakeInfo memory) {
        return _ids[_type][_id];
    }

    function unstake(string memory _id, uint _type) public {
        require(_type == 0 || _type == 1, "Only type 1 and type 2 allowed");
        require(_ids[_type][_id].who == msg.sender, "You are not original staker");
        require(_ids[_type][_id].until <= block.timestamp, "Early to unstake");

        uint amountToWithdraw = _ids[_type][_id].staked;
        _ids[_type][_id].staked = 0;
        TOKEN.transfer(msg.sender, amountToWithdraw);

        emit Unstaked(msg.sender, _id, amountToWithdraw, _type);
    }

    function pay(string memory _id) public payable {
        require(_ids[2][_id].staked == 0, "Only one pay per token per game allowed");

        _ids[2][_id].who = msg.sender;
        _ids[2][_id].staked = msg.value;

        bool success;
        (success,) = address(rewardsWallet).call{value : address(this).balance}("");

        emit Staked(msg.sender, _id, msg.value, 2);
    }

    function withdrawTokens() onlyOwner public { // emergency withdraw
        TOKEN.transfer(owner(), TOKEN.balanceOf(address(this)));
    }

    function updateWallet(address newWallet) public onlyOwner {
        rewardsWallet = newWallet;
    }

    event Staked(address indexed staker, string indexed id, uint indexed value, uint stake_type);
    event Unstaked(address indexed staker, string indexed id, uint indexed value, uint stake_type);
}


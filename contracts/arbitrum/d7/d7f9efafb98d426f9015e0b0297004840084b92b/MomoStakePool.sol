// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;


import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

import { ABDKMath64x64 } from "./ABDKMath64x64.sol";

contract MomoStakePool is Ownable {

    using SafeMath for uint256;
    using SafeERC20  for IERC20;

    struct UserInfo {
        uint256 balance;
        uint256 bonus;
        uint256 totalBonus;
        uint256 settlementDay;
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 pendingBonus;
        uint256 totalBonus;
    }

    IERC20 public poolToken;
    uint256 public maxStakingPerUser;
    uint256 public ratioPerDay = 350000000000000;

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor(
        IERC20 _poolToken,
        uint256 _maxStakingPerUser
    ) {
        poolToken = _poolToken;
        maxStakingPerUser = _maxStakingPerUser;
    }

    function setMaxStakingPerUser(uint256 amount) public onlyOwner {
        maxStakingPerUser = amount;
    }

    function setRatioPerDay(uint256 ratio) public onlyOwner {
        ratioPerDay = ratio;
    }

    function deposit(uint256 _amount) public {

        UserInfo storage user = userInfo[msg.sender];
        require(_amount.add(user.balance) <= maxStakingPerUser, 'Exception: exceed max stake');

        uint256 curDay = block.timestamp / 86400;
        if (user.settlementDay < curDay) {
            
            if (user.balance > 0) {
                uint256 interest = compound(user.balance, ratioPerDay, (curDay - user.settlementDay));

                user.balance = user.balance.add(interest);
                user.bonus = user.bonus.add(interest);
                user.totalBonus = user.totalBonus.add(interest);
            }

            user.settlementDay = curDay;
        }

        if (_amount > 0) {
            poolToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.balance = user.balance.add(_amount);
        }

        emit Deposit(msg.sender, _amount);
    }


    function withdraw(uint256 _amount) public {

        UserInfo storage user = userInfo[msg.sender];

        uint256 curDay = block.timestamp / 86400;
        if (user.settlementDay < curDay) {

            if (user.balance > 0) {
                uint256 interest = compound(user.balance, ratioPerDay, (curDay - user.settlementDay));

                user.balance = user.balance.add(interest);
                user.totalBonus = user.totalBonus.add(interest);
            }

            user.settlementDay = curDay;
        }

        require(user.balance >= _amount, "Exception: Withdraw with insufficient balance");

        if (_amount > 0) {
            user.bonus = 0;
            user.balance = user.balance.sub(_amount);
            
            poolToken.safeTransfer(address(msg.sender), _amount);
        }

        emit Withdraw(msg.sender, _amount);
    }

    function compound(uint256 principal, uint256 r, uint256 n) public pure returns(uint) {
        return ABDKMath64x64.mulu(
            pow(ABDKMath64x64.add(ABDKMath64x64.fromUInt(1), ABDKMath64x64.divu(r, 10 ** 18)), n),
            principal
        );
    }

    function pow(int128 _x, uint256 _n) public pure returns(int128 r) {
        r = ABDKMath64x64.fromUInt(1);
        while (_n > 0) {
            if (_n % 2 == 1) {
                r = ABDKMath64x64.mul(r, _x);
                _n -= 1;
            } else {
                _x = ABDKMath64x64.mul(_x, _x);
                _n /= 2;
            }
        }
    }

    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner {
        require(_amount <= poolToken.balanceOf(address(this)), 'Exception: not enough token');
        poolToken.safeTransfer(address(msg.sender), _amount);
    }

    function getUserView(address account) public view returns(UserView memory) {

        UserInfo memory user = userInfo[account];

        uint256 staked = 0;
        uint256 curBonus = 0;
        uint256 accBonus = 0;

        if (user.balance > 0) {
            staked = user.balance - user.bonus;
            curBonus = user.bonus;
            accBonus = user.totalBonus;

            uint256 curDay = block.timestamp / 86400;
            if (curDay > user.settlementDay) {
                uint256 interest = compound(user.balance, ratioPerDay, (curDay - user.settlementDay));
                curBonus += interest;
                accBonus += interest;
            }
        }

        return
        UserView({
            stakedAmount: staked,
            pendingBonus: curBonus,
            totalBonus: accBonus
        });
    }

}

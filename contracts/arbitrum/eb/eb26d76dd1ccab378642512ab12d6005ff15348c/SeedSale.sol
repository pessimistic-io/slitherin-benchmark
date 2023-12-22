// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function decimals() external view returns (uint8);
}

contract SeedSale is Ownable {
    IERC20 public raiseToken;
    mapping(address => uint256) public balances;
    address[] public allBalances;
    uint256 public softCap; // only used in UI
    uint256 public hardCap;
    uint256 public totalBalance;
    address payable public raiseReceiver;
    bool public isClosed;

    event Donate(address indexed user, uint256 amount);

    constructor(address payable _raiseReceiver, IERC20 _raiseToken, uint256 _softCap, uint256 _hardCap) {
        uint256 decimals = _raiseToken.decimals();
        raiseReceiver = _raiseReceiver;
        raiseToken = _raiseToken;
        softCap = _softCap * 10 ** decimals;
        hardCap = _hardCap * 10 ** decimals;
    }

    function open() public view returns (bool) {
        return !isClosed && totalBalance < hardCap;
    }

    function donate(uint256 _amount) public {
        require(open(), "ERR:NOT_OPEN");

        if (totalBalance + _amount > hardCap) {
            _amount = hardCap - totalBalance;
        }

        address user = msg.sender;
        require(raiseToken.allowance(user, address(this)) >= _amount, "ERR:ALLOWANCE");

        if (balances[user] == 0) {
            allBalances.push(user);
        }

        require(raiseToken.transferFrom(user, raiseReceiver, _amount), "ERR:TRANSFER_FAIL");

        unchecked {
            balances[user] += _amount;
            totalBalance += _amount;
        }

        emit Donate(user, _amount);
    }

    function numberOfDonors() external view returns (uint256) {
        return allBalances.length;
    }

    function setClosed(bool _closed) public onlyOwner {
        isClosed = _closed;
    }

    function setCaps(uint256 _softCap, uint256 _hardCap) public onlyOwner {
        uint256 decimals = raiseToken.decimals();
        softCap = _softCap * 10 ** decimals;
        hardCap = _hardCap * 10 ** decimals;
    }

    function setRaiseReceiver(address payable _raiseReceiver) public onlyOwner {
        raiseReceiver = _raiseReceiver;
    }

    function withdrawETH() external onlyOwner {
        raiseReceiver.transfer(address(this).balance);
    }

    function withdraw(IERC20 _token) external onlyOwner {
        _token.transfer(raiseReceiver, _token.balanceOf(address(this)));
    }
}


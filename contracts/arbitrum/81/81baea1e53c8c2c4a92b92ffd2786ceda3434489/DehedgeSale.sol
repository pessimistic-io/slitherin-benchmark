// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18 <0.9.0;

import "./Ownable.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function decimals() external view returns (uint8);
}

contract DehedgeSale is Ownable {
    IERC20 public raiseToken =
        IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address payable public raiseReceiver =
        payable(0xBeD86bad02560EdA4d71711c073B16524fA6816d);
    mapping(address => uint256) public balances;
    address[] public allBalances;
    uint256 public hardCap;
    uint256 private totalBalance;
    bool private isClosed;

    event Deposit(address indexed user, uint256 amount);

    constructor(uint256 _hardCap) {
        hardCap = _hardCap * 10 ** raiseToken.decimals();
    }

    function open() public view returns (bool) {
        return !isClosed && totalBalance < hardCap;
    }

    function deposit(uint256 _amount) public {
        require(open(), "ERR:NOT_OPEN");

        if (totalBalance + _amount > hardCap) {
            _amount = hardCap - totalBalance;
        }

        address user = msg.sender;
        require(
            raiseToken.allowance(user, address(this)) >= _amount,
            "ERR:ALLOWANCE"
        );

        if (balances[user] == 0) {
            allBalances.push(user);
        }

        require(
            raiseToken.transferFrom(user, raiseReceiver, _amount),
            "ERR:TRANSFER_FAIL"
        );

        unchecked {
            balances[user] += _amount;
            totalBalance += _amount;
        }

        emit Deposit(user, _amount);
    }

    function numberOfDepositors() external view returns (uint256) {
        return allBalances.length;
    }

    function setClosed(bool _closed) public onlyOwner {
        isClosed = _closed;
    }

    function setHardCap(uint256 _hardCap) public onlyOwner {
        hardCap = _hardCap * 10 ** raiseToken.decimals();
    }

    function withdrawETH() external onlyOwner {
        raiseReceiver.transfer(address(this).balance);
    }

    function withdraw(IERC20 _token) external onlyOwner {
        _token.transfer(raiseReceiver, _token.balanceOf(address(this)));
    }
}


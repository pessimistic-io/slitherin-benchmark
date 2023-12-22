// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

contract Wallet is Ownable {

    using SafeMath for uint256;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);


    IERC20 internal lpToken;

    mapping (address => uint256) public balances;

    address[] internal usersArray;
    mapping (address => bool) internal users;


    constructor(address _lpTokenAddress) {
        lpToken = IERC20(_lpTokenAddress);
    }


    function getBalance() external view returns (uint256) {
        return balances[msg.sender];
    }


    function deposit(uint256 amount) public {
        require(amount > 0, "Deposit amount should not be 0");
        require(lpToken.allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");

        balances[msg.sender] = balances[msg.sender].add(amount);

        // remember addresses that deposited tokens
        if (!users[msg.sender]) {
            users[msg.sender] = true;
            usersArray.push(msg.sender);
        }
        
        lpToken.transferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) public {
        require(balances[msg.sender] >= amount, "Insufficient token balance");

        balances[msg.sender] = balances[msg.sender].sub(amount);
        lpToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }
}

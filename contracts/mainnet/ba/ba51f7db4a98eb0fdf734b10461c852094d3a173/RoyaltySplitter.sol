// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";


contract RoyaltySplitter is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
  
    address internal TreyRatcliffLedger = 0x8A2Cc795646F64C06eB4AB060F03271f13C080D1;
    address internal SuperNormalTeam = 0xb2dC04AcC5342D14833fEbfc2C500eC3E3eC53Ba;
    
    mapping (address => uint256) public balances;


    receive() external payable {}
    fallback() external payable {}

    event Deposit(address indexed from, uint256 value);

    function deposit() external payable {       
        require(msg.value > 0, "No ether was sent");       
        emit Deposit(msg.sender, msg.value);       
        balances[msg.sender] = balances[msg.sender].add(msg.value);
    }
    

    function withdraw() external {
        
        uint256 balance = address(this).balance;
        uint256 TreyRatcliffAmount = balance.mul(67).div(100); 
        uint256 SuperNormalTeamAmount = balance.mul(33).div(100);

        address payable TreyRatcliffWallet = payable(0x8A2Cc795646F64C06eB4AB060F03271f13C080D1);
        address payable SuperNormalTeamWallet = payable(0xb2dC04AcC5342D14833fEbfc2C500eC3E3eC53Ba);

        TreyRatcliffWallet.transfer(TreyRatcliffAmount);
        SuperNormalTeamWallet.transfer(SuperNormalTeamAmount);
    }
    
}

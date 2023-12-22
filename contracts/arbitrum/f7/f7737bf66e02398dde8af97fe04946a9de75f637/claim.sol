// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract ArbGames_Seed is Ownable, ReentrancyGuard {

    using SafeERC20 for IERC20;

    IERC20 public immutable tokenForClaim;

    uint128 public lockTime;

    mapping(address => uint256) public claimPending;

    constructor(IERC20 _tokenForClaim, address _owner , uint128 _lockTime) {

        require(address(_tokenForClaim) != address(0) && _owner != address(0),"zeroAddr");

        require(_lockTime >= block.timestamp, "Dates");

        tokenForClaim = _tokenForClaim;

        lockTime = _lockTime;

        _transferOwnership(_owner);
    }

    function partner(address[] calldata _users, uint256[] calldata _amounts) external onlyOwner {

        require(_users.length == _amounts.length, "Quantity does not match");

        uint256 len = _users.length;

        for (uint256 i; i < len; ) {
            claimPending[_users[i]] = _amounts[i];
            unchecked {
                ++i;
            }
        }
    }

    
    function withdraw() external onlyOwner {
        
        uint256 balance = address(this).balance;
        
        require(balance > 0, "Insufficient funds");
        
        payable(msg.sender).transfer(balance);
    }

    function retrieve() external onlyOwner {

        uint256 balance = tokenForClaim.balanceOf(address(this));

        require(balance > 0, "Insufficient funds");

        tokenForClaim.safeTransfer(msg.sender, balance);
    }

    function claimSeedround () external nonReentrant{

        require(block.timestamp > lockTime && lockTime > 0, "Not Started");

        require(claimPending[msg.sender] > 0, "No Pending");

        uint256 balance =  claimPending[msg.sender];

        claimPending[msg.sender] = 0;

        require(tokenForClaim.balanceOf(address(this)) >= balance, "Insufficient funds");

        tokenForClaim.safeTransfer(msg.sender, balance);
    }
}


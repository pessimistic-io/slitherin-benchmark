// SPDX-License-Identifier: MIT License
pragma solidity 0.8.18;
import "./ERC20.sol";

contract LiqLock {

    address public owner;
    uint256 public lockTime;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only owner.");
        _;
    }

    function lock()
      external
      onlyOwner
    {
        lockTime = block.timestamp;
    }

    function unlock(address _token)
      external
      onlyOwner
    {
        require(block.timestamp >= lockTime + 90 days, "Lock period has not passed.");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(owner, balance);
    }

}

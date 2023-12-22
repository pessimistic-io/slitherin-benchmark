// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./IERC20.sol";

contract LPLock {
    IERC20 public lpToken;
    address public depositor;
    uint256 public unlockTime;

    constructor(IERC20 _lpToken, address _depositor) {
        lpToken = _lpToken;
        depositor = _depositor;
    }

    // lock LP for 30 days
    function deposit(uint256 _amount) external onlyDepositor {
        lpToken.transferFrom(msg.sender, address(this), _amount);
        unlockTime = block.timestamp + 30 days;
    }

    // withdraw LP after unlock time
    function withdraw() external onlyDepositor {
        require(block.timestamp >= unlockTime, "Too early");
        lpToken.transfer(msg.sender, lpToken.balanceOf(address(this)));
    }

    // team can increase lock time if needed
    function addDaysToLock(uint256 _days) external onlyDepositor {
        unlockTime = block.timestamp + _days * 1 days;
    }

    // in case everything goes well with launch, team can burn LP forever voiding the lock
    function burn() external onlyDepositor {
        lpToken.transfer(address(0xdead), lpToken.balanceOf(address(this)));
    }

    modifier onlyDepositor() {
        require(msg.sender == depositor, "Only depositor");
        _;
    }
}


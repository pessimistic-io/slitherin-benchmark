// SPDX-License-Identifier: MIT

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IBun.sol";

pragma solidity ^0.8.0;

contract FullProtec is Ownable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 lockEndedTimestamp;
    }

    IBun public bun;
    uint256 public lockDuration;
    uint256 public totalStaked;
    bool public depositsEnabled;

    // Info of each user.
    mapping(address => UserInfo) public userInfo;

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event LogSetLockDuration(uint256 lockDuration);
    event LogSetDepositsEnabled(bool enabled);

    address public BUN_ADDRESS = 0x38d5de0abD9eE3de0eD0F8c8699998C65BD825b7;
    
    constructor() {
        bun = IBun(BUN_ADDRESS);
        lockDuration = 604800;
        depositsEnabled = true;
    }

    function setDepositsEnabled(bool _enabled) external onlyOwner {
        depositsEnabled = _enabled;
        emit LogSetDepositsEnabled(_enabled);
    }

    function setLockDuration(uint256 _lockDuration) external onlyOwner {
      lockDuration = _lockDuration;
      emit LogSetLockDuration(_lockDuration);
    }

    function deposit(uint256 _amount) external {
        require(depositsEnabled, "Deposits disabled");
        require(_amount > 0, "Invalid amount");

        UserInfo storage user = userInfo[msg.sender];
        user.lockEndedTimestamp = block.timestamp + lockDuration;
        IERC20(address(bun)).safeTransferFrom(address(msg.sender), address(this), _amount);
        bun.burn(_amount);

        totalStaked += _amount;
        user.amount += _amount;
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external {
        require(_amount > 0, "Invalid amount");

        UserInfo storage user = userInfo[msg.sender];
        require(user.lockEndedTimestamp <= block.timestamp, "Still locked");
        require(user.amount >= _amount, "Invalid amount");

        user.lockEndedTimestamp = block.timestamp + lockDuration;
        user.amount -= _amount;
        totalStaked -= _amount;
        bun.mint(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _amount);
    }
}

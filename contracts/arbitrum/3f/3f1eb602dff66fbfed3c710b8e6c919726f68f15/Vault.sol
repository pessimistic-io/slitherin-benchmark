// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract Vault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant TEST = "TEST";
    uint256 public constant LOCK_TIME = 2 minutes;
    address public immutable arsh;
    address public immutable xarsh;

    mapping(address => DepositInfo[]) public userToDepositInfo;

    struct DepositInfo {
        uint256 amount;
        uint256 timestamp;
        bool resolved;
    }

    event Deposit(address indexed user, uint256 indexed amount);
    event Withdraw(address indexed user, uint256 indexed amount);

    constructor(address _arsh, address _xarsh) {
        arsh = _arsh;
        xarsh = _xarsh;
    }

    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Zero amount");

        IERC20(xarsh).safeTransferFrom(msg.sender, address(this), _amount);

        DepositInfo memory depositInfo = DepositInfo(
            _amount,
            block.timestamp,
            false
        );
        userToDepositInfo[msg.sender].push(depositInfo);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw() external nonReentrant {
        require(userToDepositInfo[msg.sender].length > 0, "No deposit found");

        uint256 amount = 0;
        for (uint256 i = 0; i < userToDepositInfo[msg.sender].length; i++) {
            if (
                (block.timestamp <
                    userToDepositInfo[msg.sender][i].timestamp + LOCK_TIME) ||
                userToDepositInfo[msg.sender][i].resolved
            ) {
                continue;
            }

            amount += userToDepositInfo[msg.sender][i].amount;
            userToDepositInfo[msg.sender][i].resolved = true;
        }

        require(amount > 0, "No ARSH to withdraw");

        require(
            amount <= IERC20(arsh).balanceOf(address(this)),
            "Not enough ARSH"
        );

        IERC20(arsh).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function getUserUnlockedValue(address _user) public view returns (uint256) {
        require(userToDepositInfo[_user].length > 0, "No deposit found");

        uint256 amount = 0;
        for (uint256 i = 0; i < userToDepositInfo[_user].length; i++) {
            if (
                (block.timestamp <
                    userToDepositInfo[_user][i].timestamp + LOCK_TIME) ||
                userToDepositInfo[_user][i].resolved
            ) {
                continue;
            }

            amount += userToDepositInfo[_user][i].amount;
        }

        return amount;
    }

    function getUserLockedAmount(address _user) public view returns (uint256) {
        require(userToDepositInfo[_user].length > 0, "No deposit found");

        uint256 amount = 0;
        for (uint256 i = 0; i < userToDepositInfo[_user].length; i++) {
            if (userToDepositInfo[_user][i].resolved) {
                continue;
            }

            amount += userToDepositInfo[_user][i].amount;
        }

        return amount;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IERC20.sol";
import "./IVe.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract AirDropTeam is ReentrancyGuard{
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    uint256 internal constant LOCK_TIME = 2 * 365 * 86400;

    uint256 public startTime;

    mapping(address => uint256) public userTotalTokensToReceive;
    mapping(address => uint256) public userWithdrewAmount;

    address public owner;

    event Withdraw(address indexed buyer, uint256 token);

    constructor(uint256 _startTime, IERC20 _token) {
        startTime = _startTime;
        token = _token;
        owner = msg.sender;
    }

    function setStartTime(uint256 _startTime) external  {
        require(owner == msg.sender, "not owner");
        startTime = _startTime;
    }

    function addUsers(address[] memory _users, uint256[] memory _amounts) external {
        require(owner == msg.sender, "not owner");
        require(_users.length == _amounts.length, "amount error");
        for (uint256 i = 0; i < _users.length; i++) {
               uint256 userAmount = _amounts[i];
               address users = _users[i];
               userTotalTokensToReceive[users] = userAmount;
        }
    }

    function simulateWithdraw(
        address account
    ) external view returns (uint256, uint256) {
        return _simulateWithdraw(account);
    }

    function _simulateWithdraw(
        address account
    ) internal view returns (uint256, uint256) {
        if (userTotalTokensToReceive[account] == 0) return (0, 0);

        if (block.timestamp < startTime) return (0, 0);

        if (block.timestamp > startTime + LOCK_TIME) {
            uint256 tokensToReceive = userTotalTokensToReceive[account] -
                userWithdrewAmount[account];

            return (userTotalTokensToReceive[account], tokensToReceive);
        } else {
            uint256 totalTokensToReceive = userTotalTokensToReceive[account];

            uint timeElapsed = block.timestamp - startTime;

            uint256 releaseAmt = (totalTokensToReceive * timeElapsed) / LOCK_TIME;

            uint256 currentAvailableAmt = releaseAmt -
                userWithdrewAmount[account];

            return (userTotalTokensToReceive[account], currentAvailableAmt);
        }
    }

    function withdraw() external nonReentrant{
        require(
            block.timestamp > startTime,
            "not start."
        );
        require(
            userTotalTokensToReceive[msg.sender] > 0,
            "No withdrawable amount available"
        );

        (,uint256  currentAvailableAmt) = _simulateWithdraw(
            msg.sender
        );

        IERC20(token).safeTransfer(msg.sender, currentAvailableAmt);

        userWithdrewAmount[msg.sender] += currentAvailableAmt;

        emit Withdraw(msg.sender, currentAvailableAmt);
    }
    
}


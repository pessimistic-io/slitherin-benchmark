// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

contract WARLockerAdvisors is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public lockerAdvisors;

    IERC20 public warToken;
    uint256 public vestingDuration = 72 weeks; // 18 months
    uint256 public vestingCliff = block.timestamp + 24 weeks; // 6 months

    mapping(address => bool) public hasAllocation;
    mapping(address => uint256) public allocation;
    mapping(address => uint256) public lastWithdrawal;
    mapping(address => uint256) public totalClaimed;

    event Claim(address user, uint256 amount);
    event TokensAllocated(address user, uint256 amount);

    error NoAllocation();
    error CliffPeriod();
    error BadArrays();
    error NotEnoughTokens();
    error ClaimFinished();

    constructor(IERC20 _token) {
        warToken = _token;
    }

    function claim() external whenNotPaused nonReentrant {
        if (allocation[msg.sender] == 0) revert NoAllocation();
        if (!hasAllocation[msg.sender]) revert NoAllocation();
        if (totalClaimed[msg.sender] >= allocation[msg.sender]) revert ClaimFinished();
        if (block.timestamp < vestingCliff) revert CliffPeriod();

        if (block.timestamp > vestingCliff + vestingDuration) {
            uint256 finalAmount = availableToWithdraw(msg.sender);
            transferWar(finalAmount);
            return;
        }

        uint256 elapsedTime = block.timestamp - lastWithdrawal[msg.sender];
        uint256 availableTokens = (elapsedTime * allocation[msg.sender]) / vestingDuration;

        if (availableTokens > allocation[msg.sender]) {
            availableTokens = allocation[msg.sender];
        }

        transferWar(availableTokens);
    }

    function allocateTokens(address[] memory _users, uint256[] memory _amounts) external onlyOwner {
        if (_users.length != _amounts.length) revert BadArrays();

        for (uint256 i = 0; i < _users.length; i++) {
            allocation[_users[i]] = _amounts[i];
            lastWithdrawal[_users[i]] = vestingCliff;
            hasAllocation[_users[i]] = true;
            emit TokensAllocated(_users[i], _amounts[i]);
        }
    }

    function pauseContract() external whenNotPaused onlyOwner {
        _pause();
    }

    function unpauseContract() external whenPaused onlyOwner {
        _unpause();
    }

    function availableToWithdraw(address _address) public view returns (uint256) {
        uint256 tokensAvailable = allocation[_address] - totalClaimed[_address];
        return tokensAvailable;
    }

    function transferWar(uint256 _amount) private {
        uint256 contractBalance = warToken.balanceOf(address(this));
        if (contractBalance < _amount) revert NotEnoughTokens();

        totalClaimed[msg.sender] += _amount;
        lastWithdrawal[msg.sender] = block.timestamp;

        warToken.safeTransfer(msg.sender, _amount);

        emit Claim(msg.sender, _amount);
    }
}


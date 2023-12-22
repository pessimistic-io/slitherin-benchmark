// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import {IERC20} from "./IERC20.sol";
import {Governable} from "./Governable.sol";
import {IRewardDistributor} from "./IRewardDistributor.sol";
import {IRewardTracker} from "./IRewardTracker.sol";

contract RewardDistributorV2 is IRewardDistributor, Governable {
    address[] public rewardTokens;
    uint256 public lastDistributionTime;
    address public rewardTracker;

    mapping(address => uint256) public tokensPerIntervals;
    mapping(address => bool) public isHandler;

    event Distribute(address token, uint256 amount);
    event TokensPerIntervalChange(address rewardToken, uint256 amount);
    event SetHandler(address handler, bool isActive);
    event AddRewardToken(address _rewardToken, uint256 _amount);

    constructor(address[] memory _rewardTokens, address _rewardTracker) {
        rewardTokens = _rewardTokens;
        rewardTracker = _rewardTracker;
        isHandler[msg.sender] = true;
    }

    modifier onlyHandlerAndAbove() {
        _onlyHandlerAndAbove();
        _;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function rewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function getTokensPerIntervals(address _rewardToken) external view returns (uint256) {
        return tokensPerIntervals[_rewardToken];
    }

    function _onlyHandlerAndAbove() internal view {
        require(isHandler[msg.sender] || msg.sender == gov, "rewardDistributor: not handler");
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;

        emit SetHandler(_handler, _isActive);
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).transfer(_account, _amount);
    }

    function addRewardToken(address _rewardToken, uint256 _amount) external onlyGov {
        rewardTokens.push(_rewardToken);
        tokensPerIntervals[_rewardToken] = _amount;
        emit AddRewardToken(_rewardToken, _amount);
    }

    // migration purpose
    // do not use unless it is a migration case.
    function migrateRewardToken(uint256 _index, address _rewardToken) external onlyGov {
        rewardTokens[_index] = _rewardToken;
    }

    function getRewardTokensLength() public view returns (uint256) {
        return rewardTokens.length;
    }

    function setHandlers(address[] memory _handler, bool[] memory _isActive) external onlyGov {
        for (uint256 i = 0; i < _handler.length; i++) {
            isHandler[_handler[i]] = _isActive[i];
        }
    }

    function updateLastDistributionTime() external onlyGov {
        lastDistributionTime = block.timestamp;
    }

    function setTokensPerInterval(address _rewardToken, uint256 _amount) external onlyHandlerAndAbove {
        require(lastDistributionTime != 0, "RewardDistributor: invalid lastDistributionTime");
        IRewardTracker(rewardTracker).updateRewards();
        tokensPerIntervals[_rewardToken] = _amount;
        emit TokensPerIntervalChange(_rewardToken, _amount);
    }

    function setTokensPerIntervals(uint256[] memory _amounts) external onlyHandlerAndAbove {
        require(lastDistributionTime != 0, "RewardDistributor: invalid lastDistributionTime");
        require(_amounts.length == rewardTokens.length, "invalid input length");
        IRewardTracker(rewardTracker).updateRewards();
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 amount = _amounts[i];
            tokensPerIntervals[rewardToken] = amount;
            emit TokensPerIntervalChange(rewardToken, amount);
        }
    }

    function pendingRewards(address _rewardToken) public view returns (uint256) {
        if (block.timestamp == lastDistributionTime) {
            return 0;
        }

        uint256 timeDiff = block.timestamp - lastDistributionTime;
        return tokensPerIntervals[_rewardToken] * timeDiff;
    }

    function distribute() external returns (uint256[] memory) {
        require(msg.sender == rewardTracker, "RewardDistributor: invalid msg.sender");
        uint256 len = getRewardTokensLength();
        uint256[] memory rewardAmounts = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            address rewardToken = rewardTokens[i];
            uint256 amount = pendingRewards(rewardToken);

            if (amount == 0) {
                continue;
            }

            uint256 balance = IERC20(rewardToken).balanceOf(address(this));

            if (amount > balance) {
                amount = balance;
            }

            IERC20(rewardToken).transfer(msg.sender, amount);
            rewardAmounts[i] = amount;
            emit Distribute(rewardToken, amount);
        }

        lastDistributionTime = block.timestamp;

        return rewardAmounts;
    }
}


pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./interfaces_IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IElleriumTokenERC20.sol";

contract ElleriumLPStakingPool is Ownable, ReentrancyGuard {

    IElleriumTokenERC20 private rewardsToken;
    IERC20 private stakingToken;

    uint256 private rewardRate = 2893518; // in GWEI, 250 ELM per day
    uint256 private lastUpdateTime;
    uint256 private rewardPerTokenStored;

    mapping(address => uint256) private userRewardPerTokenPaid;
    mapping(address => uint256) private totalRewards;

    uint256 private  _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _latestDepositTime;

    bool private applyFees = true;

    address private stakingLPFeesAddress;
    uint256[] feesInterval = [60, 3600, 86400, 259200, 604800, 2592000];

    // Setters.
    function setAddresses(address _stakingToken, address _rewardsToken, address _stakingFeeAddress) external onlyOwner {
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IElleriumTokenERC20(_rewardsToken);
        stakingLPFeesAddress = _stakingFeeAddress;
    }

    function setRewardRate(uint256 _emissionRateInGWEI, bool _isFeesApply) external onlyOwner {
        rewardRate = _emissionRateInGWEI;
        applyFees = _isFeesApply;
    }

    // Check withdrawl fee for message sender.
    function getWithdrawalFees() public view returns (uint256) {
        uint256 timeDifference = block.timestamp - _latestDepositTime[msg.sender];
        if (applyFees) {
            if (timeDifference <= feesInterval[0]) { // 50% slashing fee
                return 50000;
            } else if (timeDifference <= feesInterval[1]) { // 20% if before 1st hour.
                return 20000;
            } else if (timeDifference <= feesInterval[2]) { // 10% if before 1st day.
                return 10000;
            } else if (timeDifference <= feesInterval[3]) { // 5% if before 3 days.
                return 5000;
            } else if (timeDifference <= feesInterval[4]) { // 3% if before 1 week.
                return 3000;
            } else if (timeDifference <= feesInterval[5]) { // 1% if before 1 month.
                return 1000;
            }
            return 500;
        }

        return 0;        
    }
     function getLastDepositTime() public view returns (uint256) {
         return _latestDepositTime[msg.sender];
     }

    // Getters.
    function balanceOf(address _account) external view returns (uint256) {
        return _balances[_account];
    }

    function checkTotalRewards() external view returns (uint256) {
        return totalRewards[msg.sender];
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (block.timestamp - lastUpdateTime) * rewardRate * 1e18 /_totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])
         / 1e18 + totalRewards[account];
    }

    function totalStaked() public view returns (uint256) {
        return _totalSupply;
    }

    //mutative
    function stake(uint _amount) external nonReentrant updateReward(msg.sender) {
        require(_amount > 9999);

        _totalSupply = _totalSupply +_amount;
        _balances[msg.sender] = _balances[msg.sender] + _amount;
        _latestDepositTime[msg.sender] = block.timestamp;

        stakingToken.transferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount);
    }

    function unstake(uint _amount) public nonReentrant updateReward(msg.sender) {
        require(_amount <= _balances[msg.sender]);

        _totalSupply = _totalSupply - _amount;
        _balances[msg.sender] = _balances[msg.sender] - _amount;

        uint256 timeDifference = block.timestamp - _latestDepositTime[msg.sender];
        uint256 taxFee = _amount * 100 /20000; // 0.5%
        if (applyFees) {
            if (timeDifference <= feesInterval[0]) { // 50% slashing fee
                taxFee = _amount * 100 / 200;
            } else if (timeDifference <= feesInterval[1]) { // 20% if before 1st hour.
                taxFee = _amount * 100 / 500;
            } else if (timeDifference <= feesInterval[2]) { // 10% if before 1st day.
                taxFee = _amount * 100 / 1000;
            } else if (timeDifference <= feesInterval[3]) { // 5% if before 3 days.
               taxFee = _amount * 100 / 2000;
            } else if (timeDifference <= feesInterval[4]) { // 3% if before 1 week.
                taxFee = _amount * 100 / 3333;
            } else if (timeDifference <= feesInterval[5]) { // 1% if before 1 month.
                 taxFee = _amount * 100 / 10000;
            }
        }
                
        stakingToken.transfer(stakingLPFeesAddress, taxFee);
        stakingToken.transfer(msg.sender, _amount - taxFee);

        emit Unstaked(msg.sender, _amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = totalRewards[msg.sender] * 1e9;
        if (reward > 0) {
            totalRewards[msg.sender] = 0;

            rewardsToken.mint(msg.sender, reward);
            emit ClaimedReward(msg.sender, reward);
        }
    }

    function unstakeAll() external {
        uint256 balance = _balances[msg.sender];
        unstake(balance);
        getReward();
    }

    // Modifier.
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        totalRewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    function withdrawToken(address _tokenContract, uint256 _amount) external onlyOwner {
        IERC20 tokenContract = IERC20(_tokenContract);
        
        // transfer the token from address of this contract
        // to address of the user (executing the withdrawToken() function)
        tokenContract.transfer(msg.sender, _amount);
    }

    event ClaimedReward(address _from, uint256 _amount);
    event Staked(address _from, uint256 _amount);
    event Unstaked(address _from, uint256 _amount);

}

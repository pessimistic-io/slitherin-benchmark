// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IterableMappingBool.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./IxTIG.sol";
import "./IGovernanceStaking.sol";
import "./IExtraRewards.sol";

contract xTIG is IxTIG, ERC20, Ownable {

    using IterableMappingBool for IterableMappingBool.Map;

    uint256 public constant DIVISION_CONSTANT = 1e10;
    uint256 public constant EPOCH_PERIOD = 1 weeks;

    IERC20 public immutable tig;
    IGovernanceStaking public immutable staking;
    address public immutable treasury;
    address public trading;
    IExtraRewards public extraRewards;

    uint256 public vestingPeriod = 30 days;
    uint256 public earlyUnlockPenalty = 5e9;
    mapping(address => uint256) public accRewardsPerToken;
    mapping(address => mapping(address => uint256)) public userPaid; // user => token => amount
    IterableMappingBool.Map private rewardTokens;

    mapping(uint256 => uint256) public epochFeesGenerated;
    mapping(uint256 => uint256) public epochAllocation;
    mapping(uint256 => uint256) public epochAllocationClaimed;
    mapping(uint256 => mapping(address => uint256)) public feesGenerated; // 7d epoch => trader => fees
    mapping(address => uint256) public tigAssetValue;
    mapping(address => RewardBatch[]) public userRewards;

    /**
     * @dev Throws if called by any account that is not minter.
     */
    modifier onlyTrading() {
        require(msg.sender == trading, "!Trading");
        _;
    }

    constructor(string memory name_, string memory symbol_, IERC20 _tig, IGovernanceStaking _staking, address _treasury) ERC20(name_, symbol_) {
        tig = _tig;
        staking = _staking;
        treasury = _treasury;
        tig.approve(address(_staking), type(uint256).max);
    }

    function createVest() external {
        uint256 _epoch = block.timestamp / EPOCH_PERIOD - 1;
        require(epochFeesGenerated[_epoch] != 0, "No fees generated");
        uint256 _amount = epochAllocation[_epoch] * feesGenerated[_epoch][msg.sender] / epochFeesGenerated[_epoch];
        require(_amount != 0, "No fees generated by trader");
        _claim(msg.sender);
        delete feesGenerated[_epoch][msg.sender];
        epochAllocationClaimed[_epoch] += _amount;
        userRewards[msg.sender].push(RewardBatch(_amount, block.timestamp + vestingPeriod));
        _mint(msg.sender, _amount);
        _updateUserPaid(msg.sender);
        emit TigVested(msg.sender, _amount);
    }

    function claimTig() external {
        _claim(msg.sender);
        RewardBatch[] storage rewardsStorage = userRewards[msg.sender];
        RewardBatch[] memory rewards = rewardsStorage;
        delete userRewards[msg.sender];
        uint256 _length = rewards.length;
        uint256 _amount;
        for (uint256 i=0; i<_length; i++) {
            RewardBatch memory reward = rewards[i];
            if (block.timestamp >= reward.unlockTime) {
                _amount = _amount + reward.amount;
            } else {
                rewardsStorage.push(reward);
            }
        }
        require(_amount != 0, "No TIG to claim");
        _burn(msg.sender, _amount);
        staking.unstake(_amount);
        _updateUserPaid(msg.sender);
        tig.transfer(msg.sender, _amount);
        emit TigClaimed(msg.sender, _amount);
    }

    function earlyClaimTig() external {
        RewardBatch[] memory rewards = userRewards[msg.sender];
        uint256 _length = rewards.length;
        require(_length != 0, "No TIG to claim");
        _claim(msg.sender);
        delete userRewards[msg.sender];
        uint256 _unstakeAmount;
        uint256 _userAmount;
        for (uint256 i=0; i<_length; i++) {
            RewardBatch memory reward = rewards[i];
            if (block.timestamp >= reward.unlockTime) {
                _userAmount += reward.amount;
                _unstakeAmount += reward.amount;
            } else {
                _userAmount += reward.amount*(DIVISION_CONSTANT-earlyUnlockPenalty)/DIVISION_CONSTANT;
                _unstakeAmount += reward.amount;
            }
        }
        _burn(msg.sender, _unstakeAmount);
        staking.unstake(_unstakeAmount);
        uint256 _amountForTreasury = _unstakeAmount-_userAmount;
        _updateUserPaid(msg.sender);
        tig.transfer(treasury, _amountForTreasury);
        tig.transfer(msg.sender, _userAmount);
        emit EarlyTigClaimed(msg.sender, _userAmount, _amountForTreasury);
    }

    function claimFees() external {
        _claim(msg.sender);
    }

    function addFees(address _trader, address _tigAsset, uint256 _fees) external onlyTrading {
        uint256 _value = _fees * tigAssetValue[_tigAsset] / 1e18;
        feesGenerated[block.timestamp / EPOCH_PERIOD][_trader] += _value;
        epochFeesGenerated[block.timestamp / EPOCH_PERIOD] += _value;
        emit FeesAdded(_trader, _tigAsset, _fees, _value);
    }

    function addTigRewards(uint256 _epoch, uint256 _amount) external onlyOwner {
        require(_epoch >= block.timestamp / EPOCH_PERIOD, "No past epochs");
        tig.transferFrom(msg.sender, address(this), _amount);
        epochAllocation[_epoch] += _amount;
        _distribute();
        staking.stake(_amount, 0);
        emit TigRewardsAdded(msg.sender, _amount);
    }

    function setTigAssetValue(address _tigAsset, uint256 _value) external onlyOwner {
        tigAssetValue[_tigAsset] = _value;
    }

    function setTrading(address _address) external onlyOwner {
        trading = _address;
        emit TradingUpdated(_address);
    }

    function setExtraRewards(address _address) external onlyOwner {
        extraRewards = IExtraRewards(_address);
        emit SetExtraRewards(_address);
    }

    function setVestingPeriod(uint256 _time) external onlyOwner {
        vestingPeriod = _time;
        emit VestingPeriodUpdated(_time);
    }

    function setEarlyUnlockPenalty(uint256 _percent) external onlyOwner {
        require(_percent <= DIVISION_CONSTANT, "Bad percent");
        earlyUnlockPenalty = _percent;
        emit EarlyUnlockPenaltyUpdated(_percent);
    }

    function whitelistReward(address _rewardToken) external onlyOwner {
        require(!rewardTokens.get(_rewardToken), "Already whitelisted");
        rewardTokens.set(_rewardToken);
        emit TokenWhitelisted(_rewardToken);
    }

    function unwhitelistReward(address _rewardToken) external onlyOwner {
        require(rewardTokens.get(_rewardToken), "Not whitelisted");
        rewardTokens.remove(_rewardToken);
        emit TokenUnwhitelisted(_rewardToken);
    }


    function recoverTig(uint256 _epoch) external onlyOwner {
        require(_epoch < block.timestamp / EPOCH_PERIOD - 1, "Unconcluded epoch");
        uint256 _amount = epochAllocation[_epoch] - epochAllocationClaimed[_epoch];
        _distribute();
        staking.unstake(_amount);
        tig.transfer(treasury, _amount);
    }

    function contractPending(address _token) public view returns (uint256) {
        return staking.pending(address(this), _token);
    }

    function extraRewardsPending(address _token) public view returns (uint256) {
        if (address(extraRewards) == address(0)) return 0;
        return extraRewards.pending(address(this), _token);
    }

    function pending(address _user, address _token) public view returns (uint256) {
        if (stakedTigBalance() == 0 || totalSupply() == 0) return 0;
        return balanceOf(_user) * (accRewardsPerToken[_token] + (contractPending(_token)*1e18/stakedTigBalance()) + (extraRewardsPending(_token)*1e18/totalSupply())) / 1e18 - userPaid[_user][_token];
    }

    function pendingTig(address _user) public view returns (uint256) {
        RewardBatch[] memory rewards = userRewards[_user];
        uint256 _length = rewards.length;
        uint256 _amount;
        for (uint256 i=0; i<_length; i++) {
            RewardBatch memory reward = rewards[i];
            if (block.timestamp >= reward.unlockTime) {
                _amount = _amount + reward.amount;
            } else {
                break;
            }
        }   
        return _amount;     
    }

    function pendingEarlyTig(address _user) public view returns (uint256) {
        RewardBatch[] memory rewards = userRewards[_user];
        uint256 _length = rewards.length;
        uint256 _amount;
        for (uint256 i=0; i<_length; i++) {
            RewardBatch memory reward = rewards[i];
            if (block.timestamp >= reward.unlockTime) {
                _amount += reward.amount;
            } else {
                _amount += reward.amount*(DIVISION_CONSTANT-earlyUnlockPenalty)/DIVISION_CONSTANT;
            }
        }
        return _amount;  
    }

    function upcomingXTig(address _user) external view returns (uint256) {
        uint256 _epoch = block.timestamp / EPOCH_PERIOD;
        if (epochFeesGenerated[_epoch] == 0) return 0;
        return epochAllocation[_epoch] * feesGenerated[_epoch][_user] / epochFeesGenerated[_epoch];
    }

    function claimableXTig(address _user) external view returns (uint256) {
        uint256 _epoch = block.timestamp / EPOCH_PERIOD - 1;
        if (epochFeesGenerated[_epoch] == 0) return 0;
        return epochAllocation[_epoch] * feesGenerated[_epoch][_user] / epochFeesGenerated[_epoch];
    }

    function stakedTigBalance() public view returns (uint256) {
        return staking.userStaked(address(this));
    }

    function userRewardBatches(address _user) external view returns (RewardBatch[] memory) {
        return userRewards[_user];
    }

    function unclaimedAllocation(uint256 _epoch) external view returns (uint256) {
        return epochAllocation[_epoch] - epochAllocationClaimed[_epoch];
    }

    function currentEpoch() external view returns (uint256) {
        return block.timestamp / EPOCH_PERIOD;
    }

    function _claim(address _user) internal {
        _distribute();
        address[] memory _tokens = rewardTokens.keys;
        uint256 _len = _tokens.length;
        for (uint256 i=0; i<_len; i++) {
            address _token = _tokens[i];
            uint256 _pending = pending(_user, _token);
            if (_pending != 0) {
                userPaid[_user][_token] += _pending;
                IERC20(_token).transfer(_user, _pending);
                emit RewardClaimed(_user, _pending);
            }
        }
    }

    function _distribute() internal {
        uint256 _length = rewardTokens.size();
        uint256[] memory _balancesBefore = new uint256[](_length);
        for (uint256 i=0; i<_length; i++) {
            address _token = rewardTokens.getKeyAtIndex(i);
            _balancesBefore[i] = IERC20(_token).balanceOf(address(this));
        }
        if (address(extraRewards) != address(0)) {
            extraRewards.claim();
        }
        staking.claim();
        for (uint256 i=0; i<_length; i++) {
            address _token = rewardTokens.getKeyAtIndex(i);
            uint256 _amount = IERC20(_token).balanceOf(address(this)) - _balancesBefore[i];
            if (stakedTigBalance() == 0 || totalSupply() == 0) {
                IERC20(_token).transfer(treasury, _amount);
                continue;
            }
            uint256 _amountPerStakedTig = _amount*1e18/stakedTigBalance();
            uint256 _amountPerxTig = _amount*1e18/totalSupply();
            accRewardsPerToken[_token] += _amountPerStakedTig;
            IERC20(_token).transfer(treasury, (_amountPerxTig-_amountPerStakedTig)*(stakedTigBalance()-totalSupply())/1e18);
        }
    }

    function _updateUserPaid(address _user) internal {
        address[] memory _tokens = rewardTokens.keys;
        uint256 _len = _tokens.length;
        for (uint256 i=0; i<_len; i++) {
            address _token = _tokens[i];
            userPaid[_user][_token] = balanceOf(_user) * accRewardsPerToken[_token] / 1e18;
        }
    }

    function _transfer(address, address, uint256) internal override {
        revert("xTIG: No transfer");
    }
}


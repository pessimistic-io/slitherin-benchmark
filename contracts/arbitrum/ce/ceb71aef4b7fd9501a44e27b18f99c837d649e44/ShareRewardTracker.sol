// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./PausableUpgradeable.sol";
import "./IInsuranceFund.sol";
import "./IShareNFT.sol";
import "./ShareLevelAmount.sol";

contract ShareRewardTracker is
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ShareLevelAmount
{
    using SafeMath for uint256;
    using Address for address payable;

    struct UserInfo {
        uint256 level;
        uint256 highestLevel;
        uint256 amount;
        uint256 nftIndex;
        uint256 nextBurnTime;
        uint256 nextWithdrawTime;
        uint256 lastHarvestTime;
        uint256 earnings;
        uint256 rewardPerTokenOneEpochPaid;
        bool isActive;
        address referrer;
    }

    struct ReferrerInfo {
        uint256 revenue;
        uint256 shareProfit;
        address[] referees;
    }

    struct PreviousReward {
        uint256 reward;
        uint256 lastReward;
        uint256 lastBurnTime;
        uint256 lastClaimTime;
        uint256 nextClaimTime;
    }

    IInsuranceFund public insuranceFund;
    IShareNFT public shareNFT;
    address public rewardToken;
    uint256 public constant BASE_LEVEL = 1;
    uint256 public constant BASE_LEVEL_AMOUNT = 1e18;
    uint256 public constant REWARD_EXPIRED_TIME= 30 days;
    uint256 public constant SHARE_BURN_PERIOD = 30 days;
    uint256 public constant FUND_WITHDRAW_PERIOD = 7 days;
    uint256 public constant RATE_UPDATE_PERIOD = 1 days;
    uint256 private constant DIVISION_FACTOR = 10000;
    uint256 public epochDuration;
    uint256 public nextRateUpdate;
    uint256 public revenueRate;
    uint256 public shareProfitRate;
    uint256 public dailyVolatilityInterest;
    uint256 public rewardPerTokenOneEpoch;
    uint256 public shareNFTIndex;
    // 10000 is 100%, 1000 is 10%, 100 is 1%, 10 is 0.1% and 1 is 0.01%
    uint256 public protocolFeePercent;
    mapping(address => UserInfo) public users;
    address[] public joinedUsers;
    mapping(address => ReferrerInfo) public referrers;

    event DailyVolatilityInterestUpdated(uint256 _value);
    event InsuranceFundUpdated(address _address);
    event TokenUpdated(address _address);
    event ShareNFTUpdated(address _address);
    event ProtocolFeePercentUpdated(uint256 _percent);
    event RevenueRateUpdated(uint256 _rate);
    event RevenueEpochUpdated(uint256 _nextRevenueEpoch);
    event ShareProfitRateUpdated(uint256 _rate);
    event EpochDurationUpdated(uint256 _duration);
    event UserRegistered(address _address);
    event UserUnregistered(address _address);
    event UserLevelUpgrade(address _address, uint256 _amount);
    event UserCanceledUnregister(address _address);
    event Harvest(address _address, uint256 _earned);
    event RewardUpdated(address _address, uint256 _reward);
    event Withdraw(address _address, uint256 _amount);
    event RevenueWithdraw(address _address, uint256 _amount);
    event ShareProfitWithdraw(address _address, uint256 _amount);

    modifier updateReward(address account) {
        _updateReward(account,false);
        _;
    }

    modifier onlyAdmin() {
        require(admin[_msgSender()]==true, "Caller is not admin");
        _;
    }

    function initialize(
        address _rewardToken,
        address _insuranceFund,
        address _shareNFT,
        address _feeCollector
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();
        rewardToken = _rewardToken;
        insuranceFund = IInsuranceFund(_insuranceFund);
        shareNFT = IShareNFT(_shareNFT);
        shareNFTIndex = 1000000;
        protocolFeePercent = 500;
        epochDuration = 86400;
        revenueRate = 500;
        shareProfitRate = 1000;
        nextRevenueEpoch = block.timestamp.add(25 days);
        feeCollector = _feeCollector;
    }

    function register(bool isReregister, address referrerAddress) public nonReentrant whenNotPaused{
        address userAddress = _msgSender();
        UserInfo storage user = users[userAddress];
        require(user.amount == 0, "Already registered");
        uint256 newAmount = getShareLevelAmount(BASE_LEVEL);
        user.level = BASE_LEVEL;
        totalAmount = totalAmount.add(newAmount);
        if (isReregister) {
            newAmount = getShareLevelAmount(user.highestLevel);
            user.level = user.highestLevel;
        }
        _register(userAddress, user, newAmount);

        uint256 revenue = newAmount.mul(revenueRate).div(DIVISION_FACTOR);
        if(user.referrer != address(0)){
            referrers[user.referrer].revenue = referrers[user.referrer].revenue.add(revenue);
            totalRefRewards[user.referrer] = totalRefRewards[user.referrer].add(revenue);
            return;
        }
        if (referrerAddress == address(0) || user.referrer == referrerAddress) return;

        user.referrer = referrerAddress;
        referrers[referrerAddress].referees.push(userAddress);
        referrers[referrerAddress].revenue = referrers[user.referrer].revenue.add(revenue);
        totalRefRewards[user.referrer] = totalRefRewards[user.referrer].add(revenue);
    }

    function adminRegister(address account, uint256 level) public nonReentrant whenNotPaused onlyAdmin{
        UserInfo storage user = users[account];
        uint256 newAmount = getShareLevelAmount(level);
        user.level = level;
        user.highestLevel = user.highestLevel;
        _updateRegisteredUser(account, user, newAmount);
    }

    function upgrade() public updateReward(msg.sender) nonReentrant whenNotPaused{
        address userAddress = _msgSender();
        UserInfo storage user = users[userAddress];
        require(user.amount > 0, "Not register");
        uint256 newAmount = getShareLevelAmount(user.level+1);
        uint256 depositAmount = newAmount.sub(user.amount);
        totalAmount = totalAmount.add(depositAmount);
        _deposit(userAddress, depositAmount);
        user.level++;
        if (user.level > user.highestLevel) user.highestLevel = user.level;
        user.amount = newAmount;
        emit UserLevelUpgrade(userAddress, newAmount);
        if (user.referrer != address(0)) {
            uint256 revenue = depositAmount.mul(revenueRate).div(DIVISION_FACTOR);
            referrers[user.referrer].revenue = referrers[user.referrer].revenue.add(revenue);
        }
    }

    function burn() public updateReward(msg.sender) nonReentrant whenNotPaused{
        address userAddress = _msgSender();
        UserInfo storage user = users[userAddress];
        require(user.amount > 0, "Not register");
        require(block.timestamp > user.nextBurnTime, "Not time to unregister");
        PreviousReward storage previousReward = userPreviousRewards[userAddress];
        previousReward.lastReward = user.earnings;
        previousReward.reward = previousReward.reward.add(user.earnings);
        previousReward.lastBurnTime = block.timestamp;
        previousReward.lastClaimTime = previousReward.nextClaimTime;
        previousReward.nextClaimTime = block.timestamp + REWARD_EXPIRED_TIME;
        user.isActive = false;
        user.earnings = 0;
        user.nextWithdrawTime = block.timestamp + FUND_WITHDRAW_PERIOD;
        emit UserUnregistered(userAddress);
    }

    function cancelBurn() public nonReentrant whenNotPaused{
        address userAddress = _msgSender();
        UserInfo storage user = users[userAddress];
        require(user.amount > 0, "Not register");
        require(!user.isActive, "Is Active");
        PreviousReward storage previousReward = userPreviousRewards[userAddress];
        previousReward.reward = previousReward.reward.sub(previousReward.lastReward);
        previousReward.nextClaimTime = previousReward.lastClaimTime
            .add(block.timestamp.sub(previousReward.lastBurnTime));
        previousReward.lastBurnTime = 0;
        previousReward.lastBurnTime = 0;
        user.earnings = previousReward.lastReward;
        previousReward.lastReward = 0;
        user.nextWithdrawTime = 0;
        user.isActive = true;
        user.lastHarvestTime = block.timestamp;
        emit UserCanceledUnregister(userAddress);
    }

    function withdraw() public updateReward(msg.sender) nonReentrant whenNotPaused{
        address userAddress = _msgSender();
        UserInfo storage user = users[userAddress];
        require(!user.isActive, "User is active, unregister to withdraw");
        uint256 withdrawFee = user.amount.mul(protocolFeePercent).div(
            DIVISION_FACTOR
        );
        _withdraw(feeCollector, withdrawFee);
        uint256 withdrawAmount = user.amount.sub(withdrawFee);
        require(withdrawAmount > 0, "Not enough amount to withdraw");
        require(
            block.timestamp > user.nextWithdrawTime,
            "Not time to withdraw"
        );
        shareNFT.burn(user.nftIndex);
        user.level = 0;
        user.nftIndex = 0;
        user.amount = 0;
        user.nextWithdrawTime = 0;
        _withdraw(userAddress, withdrawAmount);
        emit Withdraw(userAddress, withdrawAmount);
    }

    function harvest() public updateReward(msg.sender) nonReentrant whenNotPaused{
        address userAddress = _msgSender();
        UserInfo storage user = users[userAddress];
        require( user.isActive, "User is not active" );
        uint256 earned = user.earnings;
        require(earned > 0, "Not enough amount to harvest");
        user.earnings = 0;
        user.nextBurnTime= block.timestamp+SHARE_BURN_PERIOD;
        user.lastHarvestTime = block.timestamp;
        _withdraw(userAddress, earned);
        emit Harvest(userAddress, earned);
    }

    function claimPreviousReward() public nonReentrant whenNotPaused{
        address userAddress = _msgSender();
        PreviousReward storage previousReward = userPreviousRewards[userAddress];
        require(
            block.timestamp > previousReward.nextClaimTime,
            "Not time to claim previous reward"
        );
        uint256 earned = previousReward.reward;
        require(earned > 0, "Not enough amount to claim");
        previousReward.reward = 0;
        previousReward.nextClaimTime = 0;
        _withdraw(userAddress, earned);
        emit Harvest(userAddress, earned);
    }

    function claimRevenue() public nonReentrant whenNotPaused{
        require(
            block.timestamp > nextRevenueEpoch,
            "Not time to claim revenue"
        );
        address userAddress = _msgSender();
        ReferrerInfo storage info = referrers[userAddress];
        uint256 revenue = info.revenue;
        require(revenue > 0, "Not enough amount to claim");
        info.revenue = 0;
        _withdraw(userAddress, revenue);
        emit RevenueWithdraw(userAddress,revenue);
    }

    function claimShareProfit() public nonReentrant whenNotPaused{
        address userAddress = _msgSender();
        ReferrerInfo storage info = referrers[userAddress];
        uint256 profit = info.shareProfit;
        require(profit > 0, "Not enough amount to claim");
        info.shareProfit = 0;
        _withdraw(userAddress, profit);
        emit ShareProfitWithdraw(userAddress,profit);
    }

    function earning(address account) public view returns(uint256){
        UserInfo memory user = users[account];
        if(!user.isActive){
            return 0;
        }
        if(user.lastHarvestTime.add(REWARD_EXPIRED_TIME) < block.timestamp){
            return 0;
        }
        uint256 rewardPerTokenOneEpochEarn = rewardPerTokenOneEpoch.sub(
            user.rewardPerTokenOneEpochPaid
        );
        uint256 earningTime = block.timestamp.sub(user.lastHarvestTime);
//        if(earningTime > epochDuration) earningTime = epochDuration;
        uint256 earned = user.amount.mul(rewardPerTokenOneEpochEarn).mul(earningTime).div(1e18);
        return user.earnings.add(earned);
    }

    function getRewardPerTokenOneEpoch(uint256 dailyRate) public view returns(uint256) {
        uint256 rewardPerTokenAdded = BASE_LEVEL_AMOUNT.mul(dailyRate).div(
            DIVISION_FACTOR
        ).div(epochDuration);
        return rewardPerTokenOneEpoch.add(rewardPerTokenAdded);
    }

    function setDailyVolatilityInterest(uint256 _value) public onlyAdmin {
        require(
            block.timestamp > nextRateUpdate,
            "Not time to set daily volatility interest"
        );
        emit DailyVolatilityInterestUpdated(_value);
        dailyVolatilityInterest = _value;
        nextRateUpdate = block.timestamp + RATE_UPDATE_PERIOD;
        rewardPerTokenOneEpoch = getRewardPerTokenOneEpoch(_value);
    }

    function setInsuranceFund(IInsuranceFund _insuranceFund) public onlyOwner {
        emit InsuranceFundUpdated(address(_insuranceFund));
        insuranceFund = _insuranceFund;
    }

    function setToken(address _rewardToken) public onlyOwner {
        emit TokenUpdated(_rewardToken);
        rewardToken = _rewardToken;
    }

    function setShareNFT(IShareNFT _shareNFT) public onlyOwner {
        emit ShareNFTUpdated(address(_shareNFT));
        shareNFT = _shareNFT;
    }

    function setProtocolFeePercent(uint256 _percent) public onlyOwner {
        emit ProtocolFeePercentUpdated(_percent);
        protocolFeePercent = _percent;
    }

    function setRevenueRate(uint256 _rate) public onlyAdmin {
        emit RevenueRateUpdated(_rate);
        revenueRate = _rate;
    }

    function setRevenueEpoch(uint256 _epochDuration) public onlyOwner {
        nextRevenueEpoch = block.timestamp.add(_epochDuration);
        emit RevenueRateUpdated(nextRevenueEpoch);
    }

    function setShareProfitRate(uint256 _rate) public onlyAdmin {
        emit ShareProfitRateUpdated(_rate);
        shareProfitRate = _rate;
    }

    function setEpochDuration(uint256 _duration) public onlyOwner {
        emit EpochDurationUpdated(_duration);
        epochDuration = _duration;
    }

    function setFeeCollector(address _address) public onlyOwner{
        feeCollector = _address;
    }

    function setAdmin(address _account, bool _isAdmin) public onlyOwner{
        admin[_account] = _isAdmin;
    }

    function setRewardTokenDecimal(uint256 decimal) public onlyOwner{
        rewardTokenDecimal = decimal;
    }

    function adjustDecimal(uint256 amount) public view returns (uint256){
        return amount.mul(10 ** rewardTokenDecimal).div(10 ** DEFAULT_DECIMAL);
    }

    function numberUsersJoined() public view returns(uint256){
        return joinedUsers.length;
    }

    function _deposit(address user, uint256 amount) private {
        uint256 depositAmount = adjustDecimal(amount);
        insuranceFund.deposit(depositAmount, user, rewardToken);
    }

    function _withdraw(address user, uint256 amount) private {
        uint256 withdrawAmount = adjustDecimal(amount);
        insuranceFund.withdraw(withdrawAmount, user, rewardToken);
    }

    function _updateReward(address account, bool isDailyUpdate) private {
        UserInfo storage user = users[account];
        if (!user.isActive){
            return;
        }
        if(user.lastHarvestTime.add(REWARD_EXPIRED_TIME) < block.timestamp){
            user.lastHarvestTime = block.timestamp;
            user.rewardPerTokenOneEpochPaid = rewardPerTokenOneEpoch;
            user.earnings = 0;
            return;
        }
        uint256 earned = earning(account);
        emit RewardUpdated(account, earned);
        user.earnings = earned;
        user.lastHarvestTime = block.timestamp;
        uint256 shareProfit = earned.mul(shareProfitRate).div(DIVISION_FACTOR);
        address referrer = user.referrer;
        referrers[referrer].shareProfit = referrers[referrer].shareProfit.add(shareProfit);
        totalRefRewards[referrer] = totalRefRewards[referrer].add(shareProfit);
        if(isDailyUpdate){
            user.rewardPerTokenOneEpochPaid = rewardPerTokenOneEpoch;
        }
    }

    function updateRewardForUser(uint256 start, uint256 size) public onlyAdmin {
        uint256 length = start+size;
        if (length > joinedUsers.length) {
            length = joinedUsers.length;
        }
        for(uint256 i = start; i < length; i++){
            _updateReward(joinedUsers[i],true);
        }
    }

    function _register(address userAddress, UserInfo storage user, uint256 newAmount) private{
        _deposit(userAddress, newAmount);
       _updateRegisteredUser(userAddress,user,newAmount);
    }

    function _updateRegisteredUser(address userAddress, UserInfo storage user, uint256 newAmount) private{
        user.amount = newAmount;
        if (user.rewardPerTokenOneEpochPaid == 0) {
            joinedUsers.push(userAddress);
        }
        uint256 dailyRewardPerTokenOneEpoch = BASE_LEVEL_AMOUNT.mul(dailyVolatilityInterest).div(
            DIVISION_FACTOR
        ).div(epochDuration);
        if(user.level > user.highestLevel) user.highestLevel = user.level;
        user.rewardPerTokenOneEpochPaid = rewardPerTokenOneEpoch.sub(dailyRewardPerTokenOneEpoch);
        shareNFTIndex += 1;
        shareNFT.mint(userAddress, shareNFTIndex);
        user.nftIndex = shareNFTIndex;
        user.isActive = true;
        user.lastHarvestTime= block.timestamp;
        emit UserRegistered(userAddress);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
    uint256 public nextRevenueEpoch;
    address public feeCollector;
    uint256 public totalAmount;
    mapping (address => bool) public admin;
    mapping (address => PreviousReward) public userPreviousRewards;
    uint256 public rewardTokenDecimal;
    uint256 public constant DEFAULT_DECIMAL = 18;
    mapping (address => uint256) public totalRefRewards;
}

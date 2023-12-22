// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./ERC2771Context.sol";

import "./IAffiliate.sol";
import "./IAccessContract.sol";
import "./ITreasury.sol";
import {OptionLib} from "./OptionLib.sol";

// logs
import "./console.sol";

contract Affiliate is IAffiliate, ERC2771Context, Ownable, AccessContract, ReentrancyGuard {
  
    ITreasury treasury;

    uint public constant MONTH = 30 days;
    uint public constant PCT_BASE = 100000;
    uint public constant DECIMALS = 1e6; //USDC & BLX

    address public USDC;
    address public BLX;
    //user address => token address => UserStats
    mapping(address => mapping(address => UserStats)) public stats;
    //user address => token address => reward
    mapping(address => mapping(address => uint)) public accruedRewards;
    mapping(address => mapping(address => uint)) public accruedDigitalRewards;
    //mapping(address => mapping(address => uint)) public rewards;
    mapping(address => mapping(address => uint)) public rewardsClaimed; // current period reward claimed
    mapping(address => mapping(address => uint)) public digitalRewardsClaimed; // current period reward claimed
    mapping(address => User) public users;

    Tiers[] public digital; //optionType = true //isDigital
    Tiers[] public classic; //optionType = false

    event RewardClaimed(address indexed user, address indexed token, uint amount);
    event RewardLoss(address indexed user, uint usdc, uint blx);
    event VolumeChanged(address indexed user, address token, uint amount, bool isDigital);

    mapping(address => bool) private _isOperator;

    modifier onlyOperator() {
        require(_isOperator[_msgSender()], "AFF:CALLER_NOT_ALLOWED");
        _;
    }

    // ============= OPERATOR ===============

    function isOperator(address _operator) public view returns (bool) {
        return _isOperator[_operator];
    }

    function allowOperator(address _operator) public onlyOwner {
        require(_operator != address(0), "AFF:ZERO_ADDRESS");
        _isOperator[_operator] = true;
    }

    function removeOperator(address _operator) public onlyOwner {
        require(_operator != address(0), "AFF:ZERO_ADDRESS");
        delete _isOperator[_operator];
    }

    function looseRewards(uint usdValue, uint blxValue) internal {
        if (blxValue > 0) {
            treasury.burnBlxFee(blxValue);
        }
        if (usdValue > 0) {
            //console.log("rewards sent to stakers %d", usdValue);
            // treat as platform win and distribute to staker
            treasury.registerBalanceChange(USDC, usdValue, 0, OptionLib.ProductKind.Digital);
        }
    }

    //check if month has passed (we need monthly stats)
    //clear all trading stats every month
    function _checkMonthPassed(address user) internal returns (bool newPeriod) {
        if(block.timestamp > users[user].timeSync + MONTH) {
            // start of new period
            // accrue last period unclaimed rewards
            // i.e. M1 would calculate M0 gain and accrued(claimable during M1)
            // M2 calculate M1 gain and accrue M0 would be wiped even if not claimed

            // forfeit unclaimed prior period rewards
            uint usdValue = accruedRewards[user][USDC];
            uint blxValue = accruedRewards[user][BLX];
            looseRewards(usdValue, blxValue);
            if (blxValue > 0 || usdValue > 0) {
                emit RewardLoss(user, usdValue, blxValue);
            }
            // calculate final total rewards for the immediate prior period and record ex claimed amount of current period
            (uint usdcReward, uint usdcDigitalReward) = calculateReward(user, USDC);
            (uint blxReward,) = calculateReward(user, BLX);
            uint usdcClaimed = rewardsClaimed[user][USDC];
            uint blxClaimed = rewardsClaimed[user][BLX];
            //console.log("accrued reward %d", usdcReward);
            //console.log("accrued blx reward %d", blxReward);

            // there is a possibility some is claimed during the month but the month end figure is less(more loss after claim)
            accruedRewards[user][USDC] = usdcReward > usdcClaimed ? usdcReward - usdcClaimed : 0;
            accruedRewards[user][BLX] = blxReward > blxClaimed ? blxReward - blxClaimed : 0; 
            accruedDigitalRewards[user][USDC] = usdcDigitalReward > digitalRewardsClaimed[user][USDC] ? usdcDigitalReward - digitalRewardsClaimed[user][USDC] : 0; 

            {
                // for BLX, burn excess reserved for reward(10% for self, 40% for referral)
                uint excessReserved = stats[user][BLX].fees * 10000 / PCT_BASE + stats[user][BLX].refFees * 40000 / PCT_BASE - blxClaimed - accruedRewards[user][BLX];
                //console.log("accrued blx reward %d", accruedRewards[user][BLX]);
                // burn away
                treasury.burnBlxFee(excessReserved);
            }

            // clear current(new) period state
            delete rewardsClaimed[user][USDC];
            delete rewardsClaimed[user][BLX];
            delete digitalRewardsClaimed[user][USDC];
            //delete rewards[user][USDC];
            //delete rewards[user][BLX];

            //clear stats
            delete stats[user][USDC];
            delete stats[user][BLX];
            // start new period
            users[user].timeSync = block.timestamp;
            
            return true;
        } 
    }

    constructor(address _trustedForwarder, address _usdToken, address _blx, address _treasury) ERC2771Context(_trustedForwarder) {
        require(_usdToken != address(0),  "AFF:USDC_ADDRESS_ZERO");
        require(_blx != address(0),  "AFF:BLX_ADDRESS_ZERO");
        require(_treasury != address(0),  "AFF:TREASURY_ADDRESS_ZERO");

        //Populate tiers array with initial tiers(whole UNIT, i.e. 1000 = 1000 USDC and actual amount must be scaled by 1e6 for comparison)
        //uint16[4] memory digitalTiers = [10000, 10000, 25000, 50000];
        //uint24[4] memory classicTiers = [100000, 100000, 250000, 500000];
        uint16[5] memory digitalTiers = [0, 6_000, 7_000, 8_000, 9_000];
        uint24[5] memory classicTiers = [600_000, 700_000, 800_000, 900_000, 1_000_000];

        //Trading affiliates rewards, % must match PCT_BASE so 100000 = 100% or 1000 = 1%
        //uint16[4] memory refDigitalShares = [1000, 2000, 5000, 12500];// 1/2/5/12.5
        //uint16[4] memory refClassicShares = [5000, 10000, 20000, 40000];// 5/10/20/40
        uint16[5] memory refDigitalShares = [0, 15_000, 20_000, 25_000, 30_000];
        uint16[5] memory refClassicShares = [15_000, 20_000, 25_000, 30_000, 40_000];

        //Self-traded affiliate rewards
        uint16[5] memory selfDigitalTiers = [0, 1_000, 2_500, 5_000, 5_000];
        uint24[5] memory selfClassicTiers = [0, 100_000, 250_000, 500_000, 500_000];
        //uint16[4] memory selfDigitalShares = [250, 500, 1250, 3125];// 0.25/0.5/1.25/3.125
        //uint16[4] memory selfClassicShares = [1250, 2500, 5000, 10000];// 1.25/2.5/5/10
        uint16[5] memory selfDigitalShares = [1_000, 2_000, 5_000, 10_000, 10_000];
        uint16[5] memory selfClassicShares = [1_000, 2_000, 5_000, 10_000, 10_000];

        for(uint i; i<digitalTiers.length; i++){
            digital.push(Tiers({
                volume: digitalTiers[i],
                selfVolume: selfDigitalTiers[i],
                refShare: refDigitalShares[i],
                selfShare: selfDigitalShares[i]
            }));
        }
        for(uint i; i<classicTiers.length; i++){
            classic.push(Tiers({
                volume: classicTiers[i],
                selfVolume: selfClassicTiers[i],
                refShare: refClassicShares[i],
                selfShare: selfClassicShares[i]
            }));
        }

        treasury = ITreasury(_treasury);

        USDC = _usdToken;
        BLX = _blx;

        addTrustedAddress(_msgSender());
        addTrustedAddress(address(this));
    }

    //@dev returns revenue percentage based on option and affiliate type
    //@param selfVolume self-traded investments amount
    //@param refVolume referrals investments amount
    //@param isDigital digital - true classic - false
    function getShares(uint selfVolume, uint refVolume, bool isDigital)
        internal
        view
        returns(uint refShare, uint selfShare)
    {
        Tiers[] memory tiers;
        bool refFound;
        bool selfFound;
        if(isDigital) {
            tiers = digital;
        }
        else {
            tiers = classic;
        }

        //default 0
        //refShare = 0;
        //selfShare = 0;
        //console.log("tier volume = %d", selfVolume);
        for(uint i= tiers.length; i>0; i--){
            if(refVolume > tiers[i-1].volume * DECIMALS && !refFound){
                refShare = tiers[i-1].refShare;
                refFound = true;
            }
            if(selfVolume > tiers[i-1].selfVolume * DECIMALS && !selfFound){
                selfShare = tiers[i-1].selfShare;
                selfFound = true;
            }
            if(refFound && selfFound)
                return (refShare, selfShare);
        }
    }
    //@dev adds new trader on-chain
    //@param user trader address
    function addUser(address user)
         external
         override
         onlyTrustedCaller
    {
         users[user].timeSync = block.timestamp;
    }
    //@dev adds new referral to parent address
    //@param user referral address
    //@param referer parent address
    function addReferal(address user, address referer)
         external
         override
    {
        address sender = _msgSender();
        require(referer != address(0) && user != address(0), "AFF:USER DOES NOT EXIST");
        require(sender == user || isOperator(sender),"AFF:NOT_TRUSTED_SENDER");
        require(users[user].referer == address(0), "AFF:REFERER_ALREADY_SET");
        users[user].referer = referer;
    }

    //@dev get user trading statistics
    //@param user trader address
    //@param token stats are in USDC or BLX
    function getUserStats(address user, address token)
        public
        view
        override 
        returns(UserStats memory userStats)
    {
        return stats[user][token];
    }
    //@dev get(not claim) trader rewards
    //@param user trader address
    //@param token stats are in USDC or BLX
    function showUserRewards(address user, address token)
        public
        view
        override returns(uint)
    {
        (uint reward,) = calculateReward(user, token);
        uint claimed = rewardsClaimed[user][token];
        // possible that claimed > latest calculated
        uint mtdReward = reward > claimed ? reward - claimed : 0;
        return (
            // MTD + prior M 
            mtdReward + accruedRewards[user][token]
        );
    }
    //@dev check if trader's stats are on-chain
    //@param user trader address
    function checkUserExists(address user)
        public
        view
        override returns(bool)
    {
        if(users[user].timeSync == 0)
            return false;
        else
            return true;
    }
    //@dev returns trader's referrer
    //@param user trader address
    function getParent(address user)
        public
        view
        override
        returns(address)
    {
        return users[user].referer;
    }

    //Two types of affiliates
    //1) Based on referals trading volume
    //2) Based on self-traded volume
    //@dev update trader's investment amount
    //@param user - trader address
    //@param volume investment(digital)/notional(american/classic/turbo)
    //@param token stats are in USDC or BLX
    //@param isDigital digital - true classic - false
    function updateVolume(
        address user,
        uint volume,
        address token,
        bool isDigital
    )
        external override onlyTrustedCaller
    {
        _checkMonthPassed(user);
        address referer = users[user].referer;

        if (referer != address(0) && users[referer].timeSync == 0) {
            users[referer].timeSync = block.timestamp;
        }

        if(isDigital) {
            stats[user][token].investmentDigital += volume;
            if (referer != address(0)) {
                stats[referer][token].refInvestmentDigital += volume;
                //console.log('referer digital volume %d', volume);
                //console.log('referer total digital volume %d', stats[referer][token].refInvestmentDigital);
            }
        }
        else {
            stats[user][token].volumeClassic += volume;
            if (referer != address(0)) {
                //console.log('referer classic volume %d', volume);
                //console.log('referer total digital volume %d', stats[referer][token].volumeClassic);
                stats[referer][token].refVolumeClassic += volume;
            }
        }
        
        emit VolumeChanged(user, token, volume, isDigital);
    }

    //@dev settle 'last period' reward
    //intended to be called periodically by bot
    function settleRewards(address user) external 
    {
        bool newPeriod = _checkMonthPassed(user);
        // intended for bot so revert to save unnecessary gas
        require(newPeriod,"AFF:NOTHING_TO_SETTLE");
    }

    //@dev updates trader's statistics
    //Update transaction fees if classic option
    //Update payoff if digital
    //@param user trader address
    //@param amount payoff or fees
    //@param token stats are in USDC or BLX
    //@param isDigital digital - true classic - false
    function updateStats(
        address user,
        uint volume,
        uint amount,
        address token,
        bool isDigital
    )
        external override onlyTrustedCaller
    {
        _checkMonthPassed(user);
        address referer = users[user].referer;

        if (referer != address(0) && users[referer].timeSync == 0) {
            users[referer].timeSync = block.timestamp;
        }

        if(isDigital) {
            stats[user][token].investmentDigital += volume;
            stats[user][token].payoff += amount;
            if (referer != address(0)) {
                stats[referer][token].refInvestmentDigital += volume;
                stats[referer][token].refPayoff += amount;
                users[referer].refInvestmentDigital += uint128(volume);
            }
        }
        else {
            stats[user][token].volumeClassic += volume;
            stats[user][token].fees += amount;
            if (referer != address(0)) {
                stats[referer][token].refVolumeClassic += volume;
                stats[referer][token].refFees += amount;
            }
            
            if (token == BLX) {
                // volume is shared regardless fee payment token
                // so if there is two trade one with BLX another with USDC for fee
                // volume(to calculate tier) use combined volume, only payment is token specific
                stats[user][USDC].volumeClassic += volume;
                if (referer != address(0)) {
                    stats[referer][USDC].refVolumeClassic += volume;
                }
                // for BLX, burn except potential rewards(max 50%)
                uint burnable = amount * 50000 / PCT_BASE;
                //console.log("burnable %d", burnable);
                treasury.burnBlxFee(burnable);
            } else {
                // volume is shared regardless fee payment token
                // so if there is two trade one with BLX another with USDC for fee
                // volume(to calculate tier) use combined volume, only payment is token specific
                stats[user][BLX].volumeClassic += volume;
                if (referer != address(0)) {
                    stats[referer][BLX].refVolumeClassic += volume;
                }
            }
        }
    }

    //@dev update rewards amount based on trading stats
    //@param user trader address
    //@param token stats are in USDC or BLX
    function calculateReward(address user, address token)
        public view returns(uint, uint refDigitalReward)
    {
        UserStats storage userStats = stats[user][token];
        uint refShare;
        uint selfShare;
        uint payoff = userStats.payoff;
        uint refPayoff = userStats.refPayoff;
        uint volume = userStats.investmentDigital;
        uint referalsVolume = userStats.refInvestmentDigital;
        //uint reward = rewards[user][token];
        //Calculate net profit(for binary, received - payoff = platform profit)
        uint netProfit = volume > payoff ? volume - payoff : 0;
        uint refNetProfit = referalsVolume > refPayoff ? referalsVolume - refPayoff: 0;
        //console.log("referred volume = %d", referalsVolume);
        //console.log("referred payout = %d", refPayoff);
        //console.log("refNetProfit profit = %d", refNetProfit);
        (refShare, selfShare) = getShares(
            volume,
            referalsVolume,
            true
        );
        //console.log("refShare = %d", refShare);
 
        refDigitalReward = token == BLX ? refShare * refNetProfit / PCT_BASE : _capReferredDigitalReward(user, refShare, refNetProfit);

        uint reward = refDigitalReward + selfShare * netProfit / PCT_BASE;

        (refShare, selfShare) = getShares(
            userStats.volumeClassic,
            userStats.refVolumeClassic,
            false
        );
        // for classic just % of fee collected
        //console.log("net fee = %d", userStats.fees);
        //console.log("fee share = %d", selfShare);
        //console.log("net ref fee = %d", userStats.refFees);
        //console.log("ref fee share = %d", refShare);

        reward += refShare * userStats.refFees / PCT_BASE;
        reward += selfShare * userStats.fees / PCT_BASE;

        return (reward, refDigitalReward);
    }
    function _capReferredDigitalReward(address user, uint refShare, uint refNetProfit) 
        view internal returns (uint refDigitalReward) 
    {
        // 3% of total inflow cap for referral 
        uint rewardCap = users[user].refInvestmentDigital * 3000 / PCT_BASE - users[user].refRewards;
        uint digitalRewardClaimed = digitalRewardsClaimed[user][USDC];
        //console.log("ref ltd = %d", users[user].refInvestmentDigital);
        //console.log("ref rewards cap = %d", rewardCap);
        refDigitalReward = refShare * refNetProfit / PCT_BASE;
        //console.log("ref rewards = %d", refDigitalReward);
        refDigitalReward = refDigitalReward < digitalRewardClaimed || refDigitalReward < rewardCap 
                            ? refDigitalReward 
                            : digitalRewardClaimed + (refDigitalReward > rewardCap ? rewardCap : refDigitalReward);
        //console.log("ref rewards claimed = %d", digitalRewardsClaimed[user][USDC]);

    }
    //@dev transfers reward to a trader from pool
    //@param token reward is in USDC or BLX
    function claimReward(address token)
        public override
    {
        require(token == USDC || token == BLX, "AFF:TOKEN NOT SUPPORTED");
        address sender = _msgSender();
        bool newPeriod = _checkMonthPassed(sender);
        uint rewardClaimed = rewardsClaimed[sender][token];
        uint digitalRewardClaimed = digitalRewardsClaimed[sender][token];
        uint accruedReward = accruedRewards[sender][token];
        uint reward;
        uint refDigitalReward;
        if (!newPeriod) {
            // calcuate MTD rewards
            (reward, refDigitalReward) = calculateReward(sender, token);
        }
        reward = reward > rewardClaimed ? reward - rewardClaimed : 0; //incremental current period since last claim
        uint digitalReward = refDigitalReward > digitalRewardClaimed ? refDigitalReward - digitalRewardClaimed : 0;
        uint claimableReward = reward  + accruedReward;
        require(claimableReward > 0, "AFF:NOTHING TO CLAIM");
        if(token == USDC) {
            treasury.payTokensTo(sender, claimableReward);
            // reported as 'loss'
            treasury.registerRewardPaid(claimableReward);
            
            // update LTD digital rewards claimed
            users[sender].refRewards += uint128(
                accruedDigitalRewards[sender][token] 
                + digitalReward
                );
            emit RewardClaimed(sender, USDC, claimableReward);
        }
        else {
            // must be BLX if we are here
            // follow the coding style per recommended even though
            // it is harder to understand
            treasury.payBlxTo(sender, claimableReward);
            emit RewardClaimed(sender, BLX, claimableReward);
        }
        // record current period claimed
        rewardsClaimed[sender][token] += reward;
        digitalRewardsClaimed[sender][token] += digitalReward;

        // all accrued claimed
        accruedRewards[sender][token] = 0;
        accruedDigitalRewards[sender][token] = 0;
    }
    //@dev add new tier to affiliate program
    function addTier(
        uint volume,
        uint selfVolume,
        uint refShare,
        uint selfShare,
        bool isDigital
    )
        public override onlyOwner
    {
        Tiers[] storage tiers;
        if(isDigital) {
            tiers = digital;
        }
        else {
            tiers = classic;
        }
        tiers.push(Tiers({
            volume: volume,
            selfVolume: selfVolume,
            refShare: refShare,
            selfShare: selfShare
        }));
    }
    //@dev update existing tier
    function updateTier(
        uint volume,
        uint selfVolume,
        uint refShare,
        uint selfShare,
        uint index,
        bool isDigital
    )
        public override onlyOwner
    {
        Tiers[] storage tiers;
        if(isDigital) {
            tiers = digital;
        }
        else {
            tiers = classic;
        }
        require(index < tiers.length, "Tier does not exist");
        tiers[index].volume = volume;
        tiers[index].selfVolume = selfVolume;
        tiers[index].refShare = refShare;
        tiers[index].selfShare = selfShare;
    }

    /// @dev pick ERC2771Context over Ownable
    function _msgSender() internal view override(Context, ERC2771Context)
      returns (address sender) {
      sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(Context, ERC2771Context)
      returns (bytes calldata) {
      return ERC2771Context._msgData();
    }
}


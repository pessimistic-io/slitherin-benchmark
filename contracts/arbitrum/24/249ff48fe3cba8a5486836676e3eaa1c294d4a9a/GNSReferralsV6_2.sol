// SPDX-License-Identifier: MIT
import "./Initializable.sol";

import "./StorageInterfaceV5.sol";

pragma solidity 0.8.17;

contract GNSReferralsV6_2 is Initializable {

    // CONSTANTS
    uint constant PRECISION = 1e10;
    StorageInterfaceV5 public storageT;

    // ADJUSTABLE PARAMETERS
    uint public allyFeeP;           // % (of referrer fees going to allies, eg. 10)
    uint public startReferrerFeeP;  // % (of referrer fee when 0 volume referred, eg. 75)
    uint public openFeeP;           // % (of opening fee used for referral system, eg. 33)
    uint public targetVolumeDai;    // DAI (to reach maximum referral system fee, eg. 1e8)

    // CUSTOM TYPES
    struct AllyDetails{
        address[] referrersReferred;
        uint volumeReferredDai;    // 1e18
        uint pendingRewardsToken;  // 1e18
        uint totalRewardsToken;    // 1e18
        uint totalRewardsValueDai; // 1e18
        bool active;
    }

    struct ReferrerDetails{
        address ally;
        address[] tradersReferred;
        uint volumeReferredDai;    // 1e18
        uint pendingRewardsToken;  // 1e18
        uint totalRewardsToken;    // 1e18
        uint totalRewardsValueDai; // 1e18
        bool active;
    }

    // STATE (MAPPINGS)
    mapping(address => AllyDetails) public allyDetails;
    mapping(address => ReferrerDetails) public referrerDetails;

    mapping(address => address) public referrerByTrader;

    // EVENTS
    event UpdatedAllyFeeP(uint value);
    event UpdatedStartReferrerFeeP(uint value);
    event UpdatedOpenFeeP(uint value);
    event UpdatedTargetVolumeDai(uint value);

    event AllyWhitelisted(address indexed ally);
    event AllyUnwhitelisted(address indexed ally);

    event ReferrerWhitelisted(
        address indexed referrer,
        address indexed ally
    );
    event ReferrerUnwhitelisted(address indexed referrer);
    event ReferrerRegistered(
        address indexed trader,
        address indexed referrer
    );

    event AllyRewardDistributed(
        address indexed ally,
        address indexed trader,
        uint volumeDai,
        uint amountToken,
        uint amountValueDai
    );
    event ReferrerRewardDistributed(
        address indexed referrer,
        address indexed trader,
        uint volumeDai,
        uint amountToken,
        uint amountValueDai
    );

    event AllyRewardsClaimed(
        address indexed ally,
        uint amountToken
    );
    event ReferrerRewardsClaimed(
        address indexed referrer,
        uint amountToken
    );

    function initialize(
        StorageInterfaceV5 _storageT,
        uint _allyFeeP,
        uint _startReferrerFeeP,
        uint _openFeeP,
        uint _targetVolumeDai
    ) external initializer {
        require(address(_storageT) != address(0)
            && _allyFeeP <= 50
            && _startReferrerFeeP <= 100
            && _openFeeP <= 50
            && _targetVolumeDai > 0, "WRONG_PARAMS");

        storageT = _storageT;

        allyFeeP = _allyFeeP;
        startReferrerFeeP = _startReferrerFeeP;
        openFeeP = _openFeeP;
        targetVolumeDai = _targetVolumeDai;
    }

    // MODIFIERS
    modifier onlyGov(){
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyTrading(){
        require(msg.sender == storageT.trading(), "TRADING_ONLY");
        _;
    }
    modifier onlyCallbacks(){
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");
        _;
    }

    // MANAGE PARAMETERS
    function updateAllyFeeP(uint value) external onlyGov{
        require(value <= 50, "VALUE_ABOVE_50");

        allyFeeP = value;
        
        emit UpdatedAllyFeeP(value);
    }
    function updateStartReferrerFeeP(uint value) external onlyGov{
        require(value <= 100, "VALUE_ABOVE_100");

        startReferrerFeeP = value;

        emit UpdatedStartReferrerFeeP(value);
    }
    function updateOpenFeeP(uint value) external onlyGov{
        require(value <= 50, "VALUE_ABOVE_50");

        openFeeP = value;

        emit UpdatedOpenFeeP(value);
    }
    function updateTargetVolumeDai(uint value) external onlyGov{
        require(value > 0, "VALUE_0");

        targetVolumeDai = value;
        
        emit UpdatedTargetVolumeDai(value);
    }

    // MANAGE ALLIES
    function whitelistAlly(address ally) external onlyGov{
        require(ally != address(0), "ADDRESS_0");

        AllyDetails storage a = allyDetails[ally];
        require(!a.active, "ALLY_ALREADY_ACTIVE");

        a.active = true;

        emit AllyWhitelisted(ally);
    }
    function unwhitelistAlly(address ally) external onlyGov{
        AllyDetails storage a = allyDetails[ally];
        require(a.active, "ALREADY_UNACTIVE");

        a.active = false;

        emit AllyUnwhitelisted(ally);
    }

    // MANAGE REFERRERS
    function whitelistReferrer(
        address referrer,
        address ally
    ) external onlyGov{
        
        require(referrer != address(0), "ADDRESS_0");

        ReferrerDetails storage r = referrerDetails[referrer];      
        require(!r.active, "REFERRER_ALREADY_ACTIVE");

        r.active = true;
        
        if(ally != address(0)){
            AllyDetails storage a = allyDetails[ally];
            require(a.active, "ALLY_NOT_ACTIVE");

            r.ally = ally;
            a.referrersReferred.push(referrer);
        }

        emit ReferrerWhitelisted(referrer, ally);
    }
    function unwhitelistReferrer(address referrer) external onlyGov{
        ReferrerDetails storage r = referrerDetails[referrer];
        require(r.active, "ALREADY_UNACTIVE");

        r.active = false;

        emit ReferrerUnwhitelisted(referrer);
    }

    function registerPotentialReferrer(
        address trader,
        address referrer
    ) external onlyTrading{

        ReferrerDetails storage r = referrerDetails[referrer];

        if(referrerByTrader[trader] != address(0)
        || referrer == address(0)
        || !r.active){
            return;
        }

        referrerByTrader[trader] = referrer;
        r.tradersReferred.push(trader);

        emit ReferrerRegistered(trader, referrer);
    }

    // REWARDS DISTRIBUTION
    function distributePotentialReward(
        address trader,
        uint volumeDai,
        uint pairOpenFeeP,
        uint tokenPriceDai
    ) external onlyCallbacks returns(uint){

        address referrer = referrerByTrader[trader];
        ReferrerDetails storage r = referrerDetails[referrer];

        if(!r.active){
            return 0;
        }

        uint referrerRewardValueDai = volumeDai * getReferrerFeeP(
            pairOpenFeeP,
            r.volumeReferredDai
        ) / PRECISION / 100;

        uint referrerRewardToken = referrerRewardValueDai * PRECISION / tokenPriceDai;

        storageT.handleTokens(address(this), referrerRewardToken, true);

        AllyDetails storage a = allyDetails[r.ally];
        
        uint allyRewardValueDai;
        uint allyRewardToken;

        if(a.active){
            allyRewardValueDai = referrerRewardValueDai * allyFeeP / 100;
            allyRewardToken = referrerRewardToken * allyFeeP / 100;

            a.volumeReferredDai += volumeDai;
            a.pendingRewardsToken += allyRewardToken;
            a.totalRewardsToken += allyRewardToken;
            a.totalRewardsValueDai += allyRewardValueDai;

            referrerRewardValueDai -= allyRewardValueDai;
            referrerRewardToken -= allyRewardToken;

            emit AllyRewardDistributed(
                r.ally,
                trader,
                volumeDai,
                allyRewardToken,
                allyRewardValueDai
            );
        }

        r.volumeReferredDai += volumeDai;
        r.pendingRewardsToken += referrerRewardToken;
        r.totalRewardsToken += referrerRewardToken;
        r.totalRewardsValueDai += referrerRewardValueDai;

        emit ReferrerRewardDistributed(
            referrer,
            trader,
            volumeDai,
            referrerRewardToken,
            referrerRewardValueDai
        );

        return referrerRewardValueDai + allyRewardValueDai;
    }

    // REWARDS CLAIMING
    function claimAllyRewards() external{
        AllyDetails storage a = allyDetails[msg.sender];
        uint rewardsToken = a.pendingRewardsToken;
        
        require(rewardsToken > 0, "NO_PENDING_REWARDS");

        a.pendingRewardsToken = 0;
        storageT.token().transfer(msg.sender, rewardsToken);

        emit AllyRewardsClaimed(msg.sender, rewardsToken);
    }
    function claimReferrerRewards() external{
        ReferrerDetails storage r = referrerDetails[msg.sender];
        uint rewardsToken = r.pendingRewardsToken;
        
        require(rewardsToken > 0, "NO_PENDING_REWARDS");

        r.pendingRewardsToken = 0;
        storageT.token().transfer(msg.sender, rewardsToken);

        emit ReferrerRewardsClaimed(msg.sender, rewardsToken);
    }

    // VIEW FUNCTIONS
    function getReferrerFeeP(
        uint pairOpenFeeP,
        uint volumeReferredDai
    ) public view returns(uint){

        uint maxReferrerFeeP = pairOpenFeeP * 2 * openFeeP / 100;
        uint minFeeP = maxReferrerFeeP * startReferrerFeeP / 100;

        uint feeP = minFeeP + (maxReferrerFeeP - minFeeP)
            * volumeReferredDai / 1e18 / targetVolumeDai;

        return feeP > maxReferrerFeeP ? maxReferrerFeeP : feeP;
    }

    function getPercentOfOpenFeeP(
        address trader
    ) external view returns(uint){
        return getPercentOfOpenFeeP_calc(referrerDetails[referrerByTrader[trader]].volumeReferredDai);
    }

    function getPercentOfOpenFeeP_calc(
        uint volumeReferredDai
    ) public view returns(uint resultP){
        resultP = (openFeeP * (
            startReferrerFeeP * PRECISION +
            volumeReferredDai * PRECISION * (100 - startReferrerFeeP) / 1e18 / targetVolumeDai)
        ) / 100;

        resultP = resultP > openFeeP * PRECISION ?
            openFeeP * PRECISION :
            resultP;
    }

    function getTraderReferrer(
        address trader
    ) external view returns(address){
        address referrer = referrerByTrader[trader];

        return referrerDetails[referrer].active ? referrer : address(0);
    }
    function getReferrersReferred(
        address ally
    ) external view returns (address[] memory){
        return allyDetails[ally].referrersReferred;
    }
    function getTradersReferred(
        address referred
    ) external view returns (address[] memory){
        return referrerDetails[referred].tradersReferred;
    }
}

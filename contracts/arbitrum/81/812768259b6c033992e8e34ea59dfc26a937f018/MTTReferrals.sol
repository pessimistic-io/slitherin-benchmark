// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;
import "./Initializable.sol";
import "./UniswapRouterInterfaceV5.sol";
import "./TokenInterfaceV5.sol";
import "./NftInterfaceV5.sol";
import "./VaultInterfaceV5.sol";
import "./PairsStorageInterfaceV6.sol";
import "./StorageInterfaceV5.sol";
import "./AggregatorInterfaceV6_2.sol";
import "./NftRewardsInterfaceV6.sol";

contract MTTReferrals is Initializable {
    // CONSTANTS
    uint256 constant PRECISION = 1e10;
    StorageInterfaceV5 public storageT;

    // ADJUSTABLE PARAMETERS
    uint256 public allyFeeP; // % (of referrer fees going to allies, eg. 10)
    uint256 public startReferrerFeeP; // % (of referrer fee when 0 volume referred, eg. 75)
    uint256 public openFeeP; // % (of opening fee used for referral system, eg. 33)
    uint256 public targetVolumeDai; // DAI (to reach maximum referral system fee, eg. 1e8)

    // CUSTOM TYPES
    struct AllyDetails {
        address[] referrersReferred;
        uint256 volumeReferredDai; // 1e18
        uint256 pendingRewardsToken; // 1e18
        uint256 totalRewardsToken; // 1e18
        uint256 totalRewardsValueDai; // 1e18
        bool active;
    }

    struct ReferrerDetails {
        address ally;
        address[] tradersReferred;
        uint256 volumeReferredDai; // 1e18
        uint256 pendingRewardsToken; // 1e18
        uint256 totalRewardsToken; // 1e18
        uint256 totalRewardsValueDai; // 1e18
        bool active;
    }

    // STATE (MAPPINGS)
    mapping(address => AllyDetails) public allyDetails;
    mapping(address => ReferrerDetails) public referrerDetails;

    mapping(address => address) public referrerByTrader;

    // EVENTS
    event UpdatedAllyFeeP(uint256 value);
    event UpdatedStartReferrerFeeP(uint256 value);
    event UpdatedOpenFeeP(uint256 value);
    event UpdatedTargetVolumeDai(uint256 value);

    event AllyWhitelisted(address indexed ally);
    event AllyUnwhitelisted(address indexed ally);

    event ReferrerWhitelisted(address indexed referrer, address indexed ally);
    event ReferrerUnwhitelisted(address indexed referrer);
    event ReferrerRegistered(address indexed trader, address indexed referrer);

    event AllyRewardDistributed(
        address indexed ally,
        address indexed trader,
        uint256 volumeDai,
        uint256 amountToken,
        uint256 amountValueDai
    );
    event ReferrerRewardDistributed(
        address indexed referrer,
        address indexed trader,
        uint256 volumeDai,
        uint256 amountToken,
        uint256 amountValueDai
    );

    event AllyRewardsClaimed(address indexed ally, uint256 amountToken);
    event ReferrerRewardsClaimed(address indexed referrer, uint256 amountToken);

    function initialize(
        StorageInterfaceV5 _storageT,
        uint256 _allyFeeP,
        uint256 _startReferrerFeeP,
        uint256 _openFeeP,
        uint256 _targetVolumeDai
    ) external initializer {
        require(
            address(_storageT) != address(0) &&
                _allyFeeP <= 50 &&
                _startReferrerFeeP <= 100 &&
                _openFeeP <= 50 &&
                _targetVolumeDai > 0,
            "WRONG_PARAMS"
        );

        storageT = _storageT;

        allyFeeP = _allyFeeP;
        startReferrerFeeP = _startReferrerFeeP;
        openFeeP = _openFeeP;
        targetVolumeDai = _targetVolumeDai;
    }

    // MODIFIERS
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyTrading() {
        require(msg.sender == storageT.trading(), "TRADING_ONLY");
        _;
    }
    modifier onlyCallbacks() {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");
        _;
    }

    // MANAGE PARAMETERS
    function updateAllyFeeP(uint256 value) external onlyGov {
        require(value <= 50, "VALUE_ABOVE_50");

        allyFeeP = value;

        emit UpdatedAllyFeeP(value);
    }

    function updateStartReferrerFeeP(uint256 value) external onlyGov {
        require(value <= 100, "VALUE_ABOVE_100");

        startReferrerFeeP = value;

        emit UpdatedStartReferrerFeeP(value);
    }

    function updateOpenFeeP(uint256 value) external onlyGov {
        require(value <= 50, "VALUE_ABOVE_50");

        openFeeP = value;

        emit UpdatedOpenFeeP(value);
    }

    function updateTargetVolumeDai(uint256 value) external onlyGov {
        require(value > 0, "VALUE_0");

        targetVolumeDai = value;

        emit UpdatedTargetVolumeDai(value);
    }

    // MANAGE ALLIES
    function whitelistAlly(address ally) external onlyGov {
        require(ally != address(0), "ADDRESS_0");

        AllyDetails storage a = allyDetails[ally];
        require(!a.active, "ALLY_ALREADY_ACTIVE");

        a.active = true;

        emit AllyWhitelisted(ally);
    }

    function unwhitelistAlly(address ally) external onlyGov {
        AllyDetails storage a = allyDetails[ally];
        require(a.active, "ALREADY_UNACTIVE");

        a.active = false;

        emit AllyUnwhitelisted(ally);
    }

    // Register REFERRERS
    function whitelistReferrer(address referrer, address ally) external {
        require(referrer != address(0), "ADDRESS_0");

        ReferrerDetails storage r = referrerDetails[referrer];
        require(!r.active, "REFERRER_ALREADY_ACTIVE");

        r.active = true;

        if (ally != address(0)) {
            AllyDetails storage a = allyDetails[ally];
            require(a.active, "ALLY_NOT_ACTIVE");

            r.ally = ally;
            a.referrersReferred.push(referrer);
        }

        emit ReferrerWhitelisted(referrer, ally);
    }

    function unwhitelistReferrer(address referrer) external onlyGov {
        ReferrerDetails storage r = referrerDetails[referrer];
        require(r.active, "ALREADY_UNACTIVE");

        r.active = false;

        emit ReferrerUnwhitelisted(referrer);
    }

    function registerPotentialReferrer(address trader, address referrer)
        external
        onlyTrading
    {
        ReferrerDetails storage r = referrerDetails[referrer];

        if (
            referrerByTrader[trader] != address(0) ||
            referrer == address(0) ||
            !r.active
        ) {
            return;
        }

        referrerByTrader[trader] = referrer;
        r.tradersReferred.push(trader);

        emit ReferrerRegistered(trader, referrer);
    }

    // REWARDS DISTRIBUTION
    function distributePotentialReward(
        address trader,
        uint256 volumeDai,
        uint256 pairOpenFeeP,
        uint256
    ) external onlyCallbacks returns (uint256) {
        address referrer = referrerByTrader[trader];
        ReferrerDetails storage r = referrerDetails[referrer];

        if (!r.active) {
            return 0;
        }

        uint256 referrerRewardValueDai = (volumeDai *
            getReferrerFeeP(pairOpenFeeP, r.volumeReferredDai)) /
            PRECISION /
            100;

        uint256 referrerRewardToken = referrerRewardValueDai;
        //storageT.handleTokens(address(this), referrerRewardToken, true);

        AllyDetails storage a = allyDetails[r.ally];

        uint256 allyRewardValueDai;
        uint256 allyRewardToken;

        if (a.active) {
            allyRewardValueDai = (referrerRewardValueDai * allyFeeP) / 100;
            allyRewardToken = (referrerRewardToken * allyFeeP) / 100;

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
    function claimAllyRewards() external {
        AllyDetails storage a = allyDetails[msg.sender];
        uint256 rewardsToken = a.pendingRewardsToken;

        require(rewardsToken > 0, "NO_PENDING_REWARDS");

        a.pendingRewardsToken = 0;
        //storageT.token().transfer(msg.sender, rewardsToken);
        //transfer USDC to refferer
        storageT.transferDai(address(storageT), msg.sender, rewardsToken);
        emit AllyRewardsClaimed(msg.sender, rewardsToken);
    }

    function claimReferrerRewards() external {
        ReferrerDetails storage r = referrerDetails[msg.sender];
        uint256 rewardsToken = r.pendingRewardsToken;

        require(rewardsToken > 0, "NO_PENDING_REWARDS");

        r.pendingRewardsToken = 0;
        //storageT.token().transfer(msg.sender, rewardsToken);
        storageT.transferDai(address(storageT), msg.sender, rewardsToken);
        emit ReferrerRewardsClaimed(msg.sender, rewardsToken);
    }

    // VIEW FUNCTIONS
    function getReferrerFeeP(uint256 pairOpenFeeP, uint256 volumeReferredDai)
        public
        view
        returns (uint256)
    {
        uint256 maxReferrerFeeP = (pairOpenFeeP * 2 * openFeeP) / 100;
        uint256 minFeeP = (maxReferrerFeeP * startReferrerFeeP) / 100;

        uint256 feeP = minFeeP +
            ((maxReferrerFeeP - minFeeP) * volumeReferredDai) /
            1e18 /
            targetVolumeDai;

        return feeP > maxReferrerFeeP ? maxReferrerFeeP : feeP;
    }

    function getPercentOfOpenFeeP(address trader)
        external
        view
        returns (uint256)
    {
        return
            getPercentOfOpenFeeP_calc(
                referrerDetails[referrerByTrader[trader]].volumeReferredDai
            );
    }

    function getPercentOfOpenFeeP_calc(uint256 volumeReferredDai)
        public
        view
        returns (uint256 resultP)
    {
        resultP =
            (openFeeP *
                (startReferrerFeeP *
                    PRECISION +
                    (volumeReferredDai *
                        PRECISION *
                        (100 - startReferrerFeeP)) /
                    1e18 /
                    targetVolumeDai)) /
            100;

        resultP = resultP > openFeeP * PRECISION
            ? openFeeP * PRECISION
            : resultP;
    }

    function getTraderReferrer(address trader) external view returns (address) {
        address referrer = referrerByTrader[trader];

        return referrerDetails[referrer].active ? referrer : address(0);
    }

    function getReferrersReferred(address ally)
        external
        view
        returns (address[] memory)
    {
        return allyDetails[ally].referrersReferred;
    }

    function getTradersReferred(address referred)
        external
        view
        returns (address[] memory)
    {
        return referrerDetails[referred].tradersReferred;
    }
}


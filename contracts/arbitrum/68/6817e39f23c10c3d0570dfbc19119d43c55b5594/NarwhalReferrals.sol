// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";

import "./PairInfoInterface.sol";
import "./NarwhalReferralInterface.sol";
import "./LimitOrdersInterface.sol";


interface ITradingVault {
    function deposit(uint _amount, address _user) external;
}

contract NarwhalReferrals is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    // CONSTANTS
    StorageInterface public storageT;

    // ADJUSTABLE PARAMETERS
    uint256 public baseReferralDiscount; //% in 1000 precision, 100 = 10 %
    uint256 public baseReferralRebate; //%
    uint256 public tier3tier2RebateBonus; //%
    address public USDT;
    address public TradingVault;
    CountersUpgradeable.Counter public nonce;

    struct ReferrerDetails {
        address[] userReferralList;
        uint volumeReferredUSDT; // 1e18
        uint pendingRewards; // 1e18
        uint totalRewards; // 1e18
        bool registered;
        uint256 referralLink;
        bool canChangeReferralLink;
        address userReferredFrom;
        bool isWhitelisted;
        uint256 discount;
        uint256 rebate;
        uint256 tier;
    }

    // STATE (MAPPINGS)
    mapping(address => ReferrerDetails) public referrerDetails;
    mapping(address => bool) public isTier3Referred;
    mapping(address => address) public referral;
    mapping(address => address[]) public tier3RefList;
    mapping(address => address) public tier2ReferredTier3;
    mapping(address => mapping(address => uint256)) public tier2tier3TotalComissions;
    mapping(uint256 => address) public refLinkToUser;
    mapping(address => bool) public allowedToInteract;

    // Events
    event TradingStorageSet(address indexed storageT);
    event AllowedToInteractSet(address indexed sender, bool status);
    event BaseRebatesAndDiscountsSet(uint256 discount, uint256 rebate);
    event Tier3Tier2RebateBonusSet(uint256 tier3tier2RebateBonus);
    event TradingVaultSet(address indexed tradingVault);
    event WhitelistedAddressSet(address indexed toWhitelist, bool status, uint256 rebate, uint256 discount, uint256 tier);
    event RewardsClaimed(address indexed user, uint256 amount, bool compounded);
    event ReferralLinkChanged(address indexed user, uint256 newReferralLink);
    event UserSignedUp(address indexed user, address indexed referral);
    event ReferredKOLUnder(address indexed tier3, address indexed tier2);
    event IncrementedTier2Tier3(address indexed tier2, address indexed tier3,uint256 rewardTier2,uint256 rewardTier3,uint256 tradeSize);
    event RewardsIncremented(address user,uint256 rewards,uint256 tradeSize);

    function initialize(StorageInterface _storageT, address _tradingVault) public initializer {
        require(address(_storageT) != address(0), "ADDRESS_0");
        storageT = _storageT;
        USDT = address(storageT.USDT());
        TradingVault = _tradingVault;

        baseReferralDiscount = 100; //% in 1000 precision, 100 = 10 %
        baseReferralRebate = 100; //%
        tier3tier2RebateBonus = 100; //%
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
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
        require(msg.sender == storageT.callbacks() || allowedToInteract[msg.sender], "NOT_ALLOWED");
        _;
    }

    function getReferralDetails(
        address _user
    ) public view returns (ReferrerDetails memory) {
        ReferrerDetails memory ref = referrerDetails[_user];
        return (ref);
    }

    function getReferralDiscountAndRebate(
        address _user
    ) public view returns (uint256, uint256) {
        ReferrerDetails memory ref = referrerDetails[_user];
        return (ref.discount, ref.rebate);
    }

    function isTier3KOL(address _user) public view returns (bool) {
        return (isTier3Referred[_user]);
    }

    function getReferral(address _user) public view returns (address) {
        return (referral[_user]);
    }

    function setTradingStorage(StorageInterface _storageT) public onlyOwner {
        require(address(_storageT) != address(0), "ADDRESS_0");
        storageT = _storageT;
        emit TradingStorageSet(address(_storageT));
    }
    
    function setAllowedToInteract(address _sender, bool _status) public onlyOwner {
        allowedToInteract[_sender] = _status;
        emit AllowedToInteractSet(_sender, _status);
    }

    function setBaseRebatesAndDiscounts(
        uint256 _discount,
        uint256 _rebate
    ) public onlyOwner {
        baseReferralDiscount = _discount;
        baseReferralRebate = _rebate;
        emit BaseRebatesAndDiscountsSet(_discount, _rebate);
    }

    function setTier3Tier2RebateBonus(
        uint256 _tier3tier2RebateBonus
    ) public onlyOwner {
        tier3tier2RebateBonus = _tier3tier2RebateBonus;
        emit Tier3Tier2RebateBonusSet(_tier3tier2RebateBonus);
    }

    function setTradingVault(address _tradingVault) external onlyOwner {
        require(address(_tradingVault) != address(0), "ADDRESS_0");
        TradingVault = _tradingVault;
        emit TradingVaultSet(_tradingVault);
    }

    function setWhitelistedAddress(
        address _toWhitelist,
        bool _status,
        uint256 _rebate,
        uint256 _discount,
        uint256 _tier
    ) public onlyOwner {
        require(_toWhitelist != address(0), "No 0 addresses ser");
        ReferrerDetails storage ref = referrerDetails[_toWhitelist];
        require(ref.registered == true, "Ask the user to register first");
        require(_tier == 2 || _tier == 3, "Wrong tier");

        ref.isWhitelisted = _status;
        ref.discount = _discount;
        ref.rebate = _rebate;
        ref.tier = _tier;
        emit WhitelistedAddressSet(_toWhitelist, _status, _rebate, _discount, _tier);
    }

    function referKOLUnder(address _tier3, address _tier2) public onlyOwner {
        require(
            _tier3 != address(0) && _tier2 != address(0),
            "No 0 addresses ser"
        );
        require(_tier3 != _tier2, "No identical addresses");
        ReferrerDetails memory ref = referrerDetails[_tier3];
        ReferrerDetails memory ref2 = referrerDetails[_tier2];
        require(
            ref2.registered == true && ref.registered == true,
            "Ask the user to register first"
        );
        tier3RefList[_tier3].push(_tier2);
        tier2ReferredTier3[_tier2] = _tier3;
        isTier3Referred[_tier2] = true;
        emit ReferredKOLUnder(_tier3,_tier2);
    }

    function incrementTier2Tier3(
        address _tier2,
        uint256 _rewardTier2,
        uint256 _rewardTier3,
        uint256 _tradeSize
    ) public onlyCallbacks {
        address tier3 = tier2ReferredTier3[_tier2];
        ReferrerDetails storage refTier2 = referrerDetails[_tier2];
        ReferrerDetails storage refTier3 = referrerDetails[tier3];
        refTier2.pendingRewards += _rewardTier2;
        refTier3.pendingRewards += _rewardTier3;
        refTier2.volumeReferredUSDT += _tradeSize;
        refTier3.volumeReferredUSDT += _tradeSize;
        tier2tier3TotalComissions[_tier2][tier3] += (
            _rewardTier2.add(_rewardTier3)
        );
        emit IncrementedTier2Tier3(_tier2, tier3, _rewardTier2, _rewardTier3, _tradeSize);
    }

    function incrementRewards(
        address _user,
        uint256 _rewards,
        uint256 _tradeSize
    ) public onlyCallbacks {
        ReferrerDetails storage ref = referrerDetails[_user];
        ref.pendingRewards += _rewards;
        ref.volumeReferredUSDT += _tradeSize;
        emit RewardsIncremented(_user,_rewards,_tradeSize);
    }

    function claimRewards(bool _compound) public nonReentrant {
        ReferrerDetails storage ref = referrerDetails[msg.sender];
        require(ref.registered == true, "You are not registered");
        uint256 pendings = ref.pendingRewards;
        if (pendings > 0) {
            ref.pendingRewards = 0;
            ref.totalRewards += pendings;
            if (_compound) {
                require(IERC20Upgradeable(USDT).approve(TradingVault, pendings), "Approval failed");
                ITradingVault(TradingVault).deposit(pendings, msg.sender);
            } else {
                IERC20Upgradeable(USDT).safeTransfer(msg.sender, pendings);
            }
            emit RewardsClaimed(msg.sender, pendings, _compound);
        }
    }

    //Core functions.
    function changeReferralLink(uint256 _referralLink) public nonReentrant {
        address user = msg.sender;
        ReferrerDetails storage ref = referrerDetails[user];
        address referrer = refLinkToUser[_referralLink];
        require(
            ref.canChangeReferralLink == true && ref.registered == true,
            "You are already signed up with a link or changed it once"
        );
        require(
            referrer != address(0) && referrer != msg.sender,
            "Incorrect ref link"
        );

        ref.userReferredFrom = referrer;
        ref.canChangeReferralLink = false;

        ReferrerDetails storage refFrom = referrerDetails[referrer];
        refFrom.userReferralList.push(user);
        emit ReferralLinkChanged(msg.sender, _referralLink);
    }

    //This just signs up the user with admin ref link
    function signUp(address _user, address _referral) public nonReentrant {
        require(_user != _referral, "No identical addresses");
        require(_user != address(0), "No 0 addresses ser");
        address user;
        if (msg.sender == address(storageT)) {
            user = _user;
        } else {
            user = msg.sender;
        }

        ReferrerDetails storage ref = referrerDetails[user];

        require(ref.registered == false, "You are already registered");
        require(
            refLinkToUser[nonce.current()] == address(0),
            "Referral Link already taken"
        );

        ref.referralLink = nonce.current();
        refLinkToUser[nonce.current()] = user;
        ref.registered = true;
        nonce.increment();

        if (_referral == address(0)) {
            ref.userReferredFrom = address(0);
            referral[user] = address(0);
            ref.canChangeReferralLink = true;
            ref.discount = baseReferralDiscount;
            ref.rebate = baseReferralRebate;
        } else {
            ReferrerDetails storage refFrom = referrerDetails[_referral];
            require(refFrom.registered == true, "Referrer not registered");
            ref.userReferredFrom = _referral;
            referral[user] = _referral;

            ref.canChangeReferralLink = false;
            refFrom.userReferralList.push(user);
            ref.discount = refFrom.discount;
            ref.rebate = baseReferralRebate;
        }
        ref.tier = 1;
        emit UserSignedUp(user, _referral);
    }
}


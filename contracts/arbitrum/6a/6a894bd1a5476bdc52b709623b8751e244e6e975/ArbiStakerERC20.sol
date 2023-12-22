// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeMath} from "./SafeMath.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {IERC20} from "./IERC20.sol";
import {TransferHelper} from "./TransferHelper.sol";

import {IFactory} from "./IFactory.sol";
import {IInstanceRegistry} from "./InstanceRegistry.sol";
import {IUniversalVault} from "./ArbiVault.sol";
import {ArbiVaultFactory} from "./ArbiVaultFactory.sol";
import {IRewardPool} from "./RewardPool.sol";
import {Powered} from "./Powered.sol";
import {IERC2917} from "./IERC2917.sol";
import {ProxyFactory} from "./ProxyFactory.sol";

interface IRageQuit {
    function rageQuit() external;
}

interface IArbiStaker is IRageQuit {
    /* admin events */

    event ArbiStakerERC20Created(address rewardPool, address powerSwitch);
    event ArbiStakerERC20Funded(address token, uint256 amount);
    event BonusTokenRegistered(address token);
    event BonusTokenRemoved(address token);
    event VaultFactoryRegistered(address factory);
    event VaultFactoryRemoved(address factory);
    event AdminshipTransferred(address indexed previousAdmin, address indexed newAdmin);

    /* user events */

    event Staked(address vault, uint256 amount);
    event Unstaked(address vault, uint256 amount);
    event RageQuit(address vault);
    event RewardClaimed(address vaultFactory, address recipient, address token, uint256 amount);
    event VestedRewardClaimed(address recipient, address token, uint256 amount);

    /* data types */

    struct VaultData {
        // token address to total token stake mapping
        mapping(address => uint256) tokenStake;
        EnumerableSet.AddressSet tokens;
    }

    struct LMRewardData {
        uint256 amount;
        uint256 duration;
        uint256 startedAt;
        address rewardCalcInstance;
        EnumerableSet.AddressSet bonusTokens;
        mapping(address => uint256) bonusTokenAmounts;
    }

    struct LMRewardVestingData {
        uint256 amount;
        uint256 startedAt;
    }

    /* getter functions */
    function getBonusTokenSetLength() external view returns (uint256 length);

    function getBonusTokenAtIndex(uint256 index) external view returns (address bonusToken);

    function getVaultFactorySetLength() external view returns (uint256 length);

    function getVaultFactoryAtIndex(uint256 index) external view returns (address factory);

    function getNumVaults() external view returns (uint256 num);

    function getVaultAt(uint256 index) external view returns (address vault);

    function getNumTokensStaked() external view returns (uint256 num);

    function getTokenStakedAt(uint256 index) external view returns (address token);

    function getNumTokensStakedInVault(address vault) external view returns (uint256 num);

    function getVaultTokenAtIndex(address vault, uint256 index)
        external
        view
        returns (address vaultToken);

    function getVaultTokenStake(address vault, address token)
        external
        view
        returns (uint256 tokenStake);

    function getLMRewardData(address token)
        external
        view
        returns (
            uint256 amount,
            uint256 duration,
            uint256 startedAt,
            address rewardCalcInstance
        );

    function getLMRewardBonusTokensLength(address token) external view returns (uint256 length);

    function getLMRewardBonusTokenAt(address token, uint256 index)
        external
        view
        returns (address bonusToken, uint256 bonusTokenAmount);

    function getNumVestingLMTokenRewards(address user) external view returns (uint256 num);

    function getVestingLMTokenAt(address user, uint256 index) external view returns (address token);

    function getNumVests(address user, address token) external view returns (uint256 num);

    function getNumRewardCalcTemplates() external view returns (uint256 num);

    function getLMRewardVestingData(
        address user,
        address token,
        uint256 index
    ) external view returns (uint256 amount, uint256 startedAt);

    function isValidAddress(address target) external view returns (bool validity);

    function isValidVault(address vault, address factory) external view returns (bool validity);

    /* user functions */

    function stakeERC20(
        address vault,
        address vaultFactory,
        address token,
        uint256 amount,
        bytes calldata permission
    ) external;

    function unstakeERC20AndClaim(
        address vault,
        address vaultFactory,
        address recipient,
        address token,
        uint256 amount,
        bool claimBonusReward,
        bytes calldata permission
    ) external;

    function claimVestedRewardAll() external;

    function claimVestedRewardToken(address token) external;
}

/// @title ArbiStaker
/// @notice Reward distribution contract that handles ERC20 Tokens with Tiers
/// Access Control
/// - Power controller:
///     Can power off / shutdown the ArbiStaker
///     Can withdraw rewards from reward pool once shutdown
/// - Owner:
///     Is unable to operate on user funds due to UniversalVault
///     Is unable to operate on reward pool funds when reward pool is offline / shutdown
/// - ArbiStaker admin:
///     Can add funds to the ArbiStaker, register bonus tokens, and whitelist new vault factories
///     Is a subset of owner permissions
/// - User:
///     Can stake / unstake / ragequit / claim vested rewards
/// ArbiStaker State Machine
/// - Online:
///     ArbiStaker is operating normally, all functions are enabled
/// - Offline:
///     ArbiStaker is temporarely disabled for maintenance
///     User staking and unstaking is disabled, ragequit remains enabled
///     Users can delete their stake through rageQuit() but forego their pending reward
///     Should only be used when downtime required for an upgrade
/// - Shutdown:
///     ArbiStaker is permanently disabled
///     All functions are disabled with the exception of ragequit
///     Users can delete their stake through rageQuit()
///     Power controller can withdraw from the reward pool
///     Should only be used if Owner role is compromised
contract ArbiStakerERC20 is IArbiStaker, Powered {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* constants */
    string public constant PIONNER = "PIONNER";
    string public constant PRECURSOR = "PRECURSOR";
    string public constant INNOVATOR = "INNOVATOR";
    string public constant EARLY_ADOPTER = "EARLY_ADOPTER";
    string public constant STANDARD = "STANDARD";
    uint256 public PIONNER_LM_REWARD_MULTIPLIER_NUM = 6;
    uint256 public PIONNER_LM_REWARD_MULTIPLIER_DENOM = 2;
    uint256 public PRECURSOR_LM_REWARD_MULTIPLIER_NUM = 5;
    uint256 public PRECURSOR_LM_REWARD_MULTIPLIER_DENOM = 2;
    uint256 public INNOVATOR_LM_REWARD_MULTIPLIER_NUM = 2;
    uint256 public INNOVATOR_LM_REWARD_MULTIPLIER_DENOM = 1;
    uint256 public EARLY_ADOPTER_LM_REWARD_MULTIPLIER_NUM = 3;
    uint256 public EARLY_ADOPTER_LM_REWARD_MULTIPLIER_DENOM = 2;
    uint256 public STANDARD_LM_REWARD_MULTIPLIER_NUM = 1;
    uint256 public STANDARD_LM_REWARD_MULTIPLIER_DENOM = 1;
    uint256 public LM_REWARD_VESTING_PERIOD = 2592000; // 30 days
    uint256 public LM_REWARD_VESTING_PORTION_NUM = 1;
    uint256 public LM_REWARD_VESTING_PORTION_DENOM = 2;

    // An upper bound on the number of active tokens staked per vault is required to prevent
    // calls to rageQuit() from reverting.
    // With 30 tokens staked in a vault, ragequit costs 432811 gas which is conservatively lower
    // than the hardcoded limit of 500k gas on the vault.
    // This limit is configurable and could be increased in a future deployment.
    // Ultimately, to avoid a need for fixed upper bounds, the EVM would need to provide
    // an error code that allows for reliably catching out-of-gas errors on remote calls.
    uint256 public MAX_TOKENS_STAKED_PER_VAULT = 10;
    uint256 public MAX_BONUS_TOKENS = 10;

    /* storage */
    address public admin;
    address public rewardToken;
    address public rewardPool;

    EnumerableSet.AddressSet private _vaultSet;
    mapping(address => VaultData) private _vaults;

    EnumerableSet.AddressSet private _bonusTokenSet;
    EnumerableSet.AddressSet private _vaultFactorySet;

    EnumerableSet.AddressSet private _allStakedTokens;
    mapping(address => uint256) public stakedTokenTotal;

    mapping(address => LMRewardData) private lmRewards;

    // user to token to earned reward mapping
    mapping(address => mapping(address => uint256)) public earnedLMRewards;
    // user to token to vesting data mapping
    mapping(address => mapping(address => LMRewardVestingData[])) public vestingLMRewards;
    // user to vesting lm token rewards set
    mapping(address => EnumerableSet.AddressSet) private vestingLMTokenRewards;

    // erc2917 template names
    string[] public rewardCalcTemplateNames;
    // erc2917 template names to erc 2917 templates
    mapping(string => address) public rewardCalcTemplates;
    string public activeRewardCalcTemplate;
    event RewardCalcTemplateAdded(string indexed name, address indexed template);
    event RewardCalcTemplateActive(string indexed name, address indexed template);

    /* initializer */

    /// @notice Initizalize ArbiStaker
    /// access control: only proxy constructor
    /// state machine: can only be called once
    /// state scope: set initialization variables
    /// token transfer: none
    /// @param adminAddress address The admin address
    /// @param rewardPoolFactory address The factory to use for deploying the RewardPool
    /// @param powerSwitchFactory address The factory to use for deploying the PowerSwitch
    /// @param rewardTokenAddress address The address of the reward token for this ArbiStaker
    constructor(
        address adminAddress,
        address rewardPoolFactory,
        address powerSwitchFactory,
        address rewardTokenAddress
    ) {
        // deploy power switch
        address powerSwitch = IFactory(powerSwitchFactory).create(abi.encode(adminAddress));

        // deploy reward pool
        rewardPool = IFactory(rewardPoolFactory).create(abi.encode(powerSwitch));

        // set internal config
        admin = adminAddress;
        rewardToken = rewardTokenAddress;
        Powered._setPowerSwitch(powerSwitch);

        // emit event
        emit ArbiStakerERC20Created(rewardPool, powerSwitch);
    }

    /* admin functions */

    function _admin() private {
        require(msg.sender == admin, "not allowed");
    }

    /**
     * @dev Leaves the contract without admin. It will not be possible to call
     * `admin` functions anymore. Can only be called by the current admin.
     *
     * NOTE: Renouncing adminship will leave the contract without an admin,
     * thereby removing any functionality that is only available to the admin.
     */
    function renounceAdminship() public {
        _admin();
        emit AdminshipTransferred(admin, address(0));
        admin = address(0);
    }

    /**
     * @dev Transfers adminship of the contract to a new account (`newAdmin`).
     * Can only be called by the current admin.
     */
    function transferAdminship(address newAdmin) public {
        _admin();
        require(newAdmin != address(0), "new admin can't the zero address");
        emit AdminshipTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    /// @notice Add funds to ArbiStaker
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - only online
    /// state scope:
    ///   - none
    /// token transfer: transfer staking tokens from msg.sender to reward pool
    /// @param amount uint256 Amount of reward tokens to deposit
    function fund(address token, uint256 amount) external {
        _admin();
        require(
            _bonusTokenSet.contains(token) || token == rewardToken,
            "cannot fund with unrecognized token"
        );
        // transfer reward tokens to reward pool
        TransferHelper.safeTransferFrom(token, msg.sender, rewardPool, amount);

        // emit event
        emit ArbiStakerERC20Funded(token, amount);
    }

    /// @notice Rescue tokens from RewardPool
    /// @dev use this function to rescue tokens from RewardPool contract without distributing to stakers or triggering emergency shutdown
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - not shutdown
    /// state scope: none
    /// token transfer: transfer requested token from RewardPool to recipient
    /// @param token address The address of the token to rescue
    /// @param recipient address The address of the recipient
    /// @param amount uint256 The amount of tokens to rescue
    function rescueTokensFromRewardPool(
        address token,
        address recipient,
        uint256 amount
    ) external {
        _admin();
        // verify recipient
        require(isValidAddress(recipient), "invalid recipient");
        // transfer tokens to recipient
        IRewardPool(rewardPool).sendERC20(token, recipient, amount);
    }

    /// @notice Add vault factory to whitelist
    /// @dev use this function to enable stakes to vaults coming from the specified factory contract
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - not shutdown
    /// state scope:
    ///   - append to _vaultFactorySet
    /// token transfer: none
    /// @param factory address The address of the vault factory
    function registerVaultFactory(address factory) external {
        _admin();
        // add factory to set
        require(_vaultFactorySet.add(factory), "ArbiStaker: vault factory already registered");

        // emit event
        emit VaultFactoryRegistered(factory);
    }

    /// @notice Remove vault factory from whitelist
    /// @dev use this function to disable new stakes to vaults coming from the specified factory contract.
    ///      note: vaults with existing stakes from this factory are sill able to unstake
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - not shutdown
    /// state scope:
    ///   - remove from _vaultFactorySet
    /// token transfer: none
    /// @param factory address The address of the vault factory
    function removeVaultFactory(address factory) external {
        _admin();
        // remove factory from set
        require(_vaultFactorySet.remove(factory), "ArbiStaker: vault factory not registered");

        // emit event
        emit VaultFactoryRemoved(factory);
    }

    /// @notice Register bonus token for distribution
    /// @dev use this function to enable distribution of any ERC20 held by the RewardPool contract
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - only online
    /// state scope:
    ///   - append to _bonusTokenSet
    /// token transfer: none
    /// @param bonusToken address The address of the bonus token
    function registerBonusToken(address bonusToken) external {
        _admin();
        // verify valid bonus token
        require(isValidAddress(bonusToken), "invalid bonus token address or is already present");

        // verify bonus token count
        require(
            _bonusTokenSet.length() < MAX_BONUS_TOKENS,
            "ArbiStaker: max bonus tokens reached "
        );

        // add token to set
        _bonusTokenSet.add(bonusToken);

        // emit event
        emit BonusTokenRegistered(bonusToken);
    }

    /// @notice Remove bonus token
    /// @dev use this function to disable distribution of a token held by the RewardPool contract
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - not shutdown
    /// state scope:
    ///   - remove from _bonusTokenSet
    /// token transfer: none
    /// @param bonusToken address The address of the bonus token
    function removeBonusToken(address bonusToken) external {
        _admin();
        require(_bonusTokenSet.remove(bonusToken), "ArbiStaker: bonus token not present ");

        // emit event
        emit BonusTokenRemoved(bonusToken);
    }

    function addRewardCalcTemplate(string calldata name, address template) external {
        _admin();
        require(rewardCalcTemplates[name] == address(0), "Template already exists");
        rewardCalcTemplates[name] = template;
        if (rewardCalcTemplateNames.length == 0) {
            activeRewardCalcTemplate = name;
            emit RewardCalcTemplateActive(name, template);
        }
        rewardCalcTemplateNames.push(name);
        emit RewardCalcTemplateAdded(name, template);
    }

    function setRewardCalcActiveTemplate(string calldata name) external {
        _admin();
        require(rewardCalcTemplates[name] != address(0), "Template does not exist");
        activeRewardCalcTemplate = name;
        emit RewardCalcTemplateActive(name, rewardCalcTemplates[name]);
    }

    function startLMRewards(
        address token,
        uint256 amount,
        uint256 duration
    ) external {
        startLMRewardsToken(token, amount, duration, activeRewardCalcTemplate);
    }

    function startLMRewardsToken(
        address token,
        uint256 amount,
        uint256 duration,
        string memory rewardCalcTemplateName
    ) public {
        _admin();
        require(lmRewards[token].startedAt == 0, "A reward program already live for this token");
        require(
            rewardCalcTemplates[rewardCalcTemplateName] != address(0),
            "Reward Calculator Template does not exist"
        );
        // create reward calc clone from template
        address rewardCalcInstance =
            ProxyFactory._create(
                rewardCalcTemplates[rewardCalcTemplateName],
                abi.encodeWithSelector(IERC2917.initialize.selector)
            );
        LMRewardData storage lmrd = lmRewards[token];
        lmrd.amount = amount;
        lmrd.duration = duration;
        lmrd.startedAt = block.timestamp;
        lmrd.rewardCalcInstance = rewardCalcInstance;
    }

    function setImplementorForRewardsCalculator(address token, address newImplementor) public {
        _admin();
        require(lmRewards[token].startedAt != 0, "No reward program currently live for this token");
        address rewardCalcInstance = lmRewards[token].rewardCalcInstance;
        IERC2917(rewardCalcInstance).setImplementor(newImplementor);
    }

    function setLMRewardsPerBlock(address token, uint256 value) public onlyOnline {
        _admin();
        require(lmRewards[token].startedAt != 0, "No reward program currently live for this token");
        address rewardCalcInstance = lmRewards[token].rewardCalcInstance;
        IERC2917(rewardCalcInstance).changeInterestRatePerBlock(value);
    }

    function addBonusTokenToLMRewards(
        address lmToken,
        address bonusToken,
        uint256 bonusTokenAmount
    ) public {
        _admin();
        require(
            lmRewards[lmToken].startedAt != 0,
            "No reward program currently live for this LM token"
        );
        require(_bonusTokenSet.contains(bonusToken), "Bonus token not registered");
        lmRewards[lmToken].bonusTokens.add(bonusToken);
        lmRewards[lmToken].bonusTokenAmounts[bonusToken] = lmRewards[lmToken].bonusTokenAmounts[
            bonusToken
        ]
            .add(bonusTokenAmount);
    }

    function endLMRewards(address token, bool removeBonusTokenData) public {
        _admin();
        lmRewards[token].amount = 0;
        lmRewards[token].duration = 0;
        lmRewards[token].startedAt = 0;
        lmRewards[token].rewardCalcInstance = address(0);
        if (removeBonusTokenData) {
            for (uint256 index = 0; index < lmRewards[token].bonusTokens.length(); index++) {
                address bonusToken = lmRewards[token].bonusTokens.at(index);
                lmRewards[token].bonusTokens.remove(bonusToken);
                delete lmRewards[token].bonusTokenAmounts[bonusToken];
            }
        }
    }

    function setMaxStakesPerVault(uint256 amount) external {
        _admin();
        MAX_TOKENS_STAKED_PER_VAULT = amount;
    }

    function setMaxBonusTokens(uint256 amount) external {
        _admin();
        MAX_BONUS_TOKENS = amount;
    }

    function setPionnerLMRewardMultiplier(uint256 numerator, uint256 denominator) external {
        _admin();
        PIONNER_LM_REWARD_MULTIPLIER_NUM = numerator;
        PIONNER_LM_REWARD_MULTIPLIER_DENOM = denominator;
    }

    function setEarlyAdopterLMRewardMultiplier(uint256 numerator, uint256 denominator) external {
        _admin();
        PRECURSOR_LM_REWARD_MULTIPLIER_NUM = numerator;
        PRECURSOR_LM_REWARD_MULTIPLIER_DENOM = denominator;
    }

    function setPrecursorLMRewardMultiplier(uint256 numerator, uint256 denominator) external {
        _admin();
        INNOVATOR_LM_REWARD_MULTIPLIER_NUM = numerator;
        INNOVATOR_LM_REWARD_MULTIPLIER_DENOM = denominator;
    }

    function setInnovatorLMRewardMultiplier(uint256 numerator, uint256 denominator) external {
        _admin();
        EARLY_ADOPTER_LM_REWARD_MULTIPLIER_NUM = numerator;
        EARLY_ADOPTER_LM_REWARD_MULTIPLIER_DENOM = denominator;
    }

    function setStandardLMRewardMultiplier(uint256 numerator, uint256 denominator) external {
        _admin();
        STANDARD_LM_REWARD_MULTIPLIER_NUM = numerator;
        STANDARD_LM_REWARD_MULTIPLIER_DENOM = denominator;
    }

    function setLMRewardVestingPeriod(uint256 amount) external {
        _admin();
        LM_REWARD_VESTING_PERIOD = amount;
    }

    function setLMRewardVestingPortion(uint256 numerator, uint256 denominator) external {
        _admin();
        LM_REWARD_VESTING_PORTION_NUM = numerator;
        LM_REWARD_VESTING_PORTION_DENOM = denominator;
    }

    /* getter functions */

    function getBonusTokenSetLength() external view override returns (uint256 length) {
        return _bonusTokenSet.length();
    }

    function getBonusTokenAtIndex(uint256 index)
        external
        view
        override
        returns (address bonusToken)
    {
        return _bonusTokenSet.at(index);
    }

    function getVaultFactorySetLength() external view override returns (uint256 length) {
        return _vaultFactorySet.length();
    }

    function getVaultFactoryAtIndex(uint256 index)
        external
        view
        override
        returns (address factory)
    {
        return _vaultFactorySet.at(index);
    }

    function getNumVaults() external view override returns (uint256 num) {
        return _vaultSet.length();
    }

    function getVaultAt(uint256 index) external view override returns (address vault) {
        return _vaultSet.at(index);
    }

    function getNumTokensStaked() external view override returns (uint256 num) {
        return _allStakedTokens.length();
    }

    function getTokenStakedAt(uint256 index) external view override returns (address token) {
        return _allStakedTokens.at(index);
    }

    function getNumTokensStakedInVault(address vault) external view override returns (uint256 num) {
        return _vaults[vault].tokens.length();
    }

    function getVaultTokenAtIndex(address vault, uint256 index)
        external
        view
        override
        returns (address vaultToken)
    {
        return _vaults[vault].tokens.at(index);
    }

    function getVaultTokenStake(address vault, address token)
        external
        view
        override
        returns (uint256 tokenStake)
    {
        return _vaults[vault].tokenStake[token];
    }

    function getNftTier(uint256 nftId, address nftFactory)
        public
        view
        returns (string memory tier)
    {
        uint256 serialNumber = ArbiVaultFactory(nftFactory).tokenIdToSerialNumber(nftId);
        if (serialNumber >= 1 && serialNumber <= 10) {
            tier = PIONNER;
        } else if (serialNumber >= 11 && serialNumber <= 100) {
            tier = PRECURSOR;
        } else if (serialNumber >= 101 && serialNumber <= 500) {
            tier = INNOVATOR;
        } else if (serialNumber >= 501 && serialNumber <= 1000) {
            tier = EARLY_ADOPTER;
        } else if (serialNumber >= 1001) {
            tier = STANDARD;
        }
    }

    function getNftsOfOwner(address owner, address nftFactory)
        public
        view
        returns (uint256[] memory nftIds)
    {
        uint256 balance = ArbiVaultFactory(nftFactory).balanceOf(owner);
        nftIds = new uint256[](balance);
        for (uint256 index = 0; index < balance; index++) {
            uint256 nftId = ArbiVaultFactory(nftFactory).tokenOfOwnerByIndex(owner, index);
            nftIds[index] = nftId;
        }
    }

    function getLMRewardData(address token)
        external
        view
        override
        returns (
            uint256 amount,
            uint256 duration,
            uint256 startedAt,
            address rewardCalcInstance
        )
    {
        return (
            lmRewards[token].amount,
            lmRewards[token].duration,
            lmRewards[token].startedAt,
            lmRewards[token].rewardCalcInstance
        );
    }

    function getLMRewardBonusTokensLength(address token)
        external
        view
        override
        returns (uint256 length)
    {
        return lmRewards[token].bonusTokens.length();
    }

    function getLMRewardBonusTokenAt(address token, uint256 index)
        external
        view
        override
        returns (address bonusToken, uint256 bonusTokenAmount)
    {
        return (
            lmRewards[token].bonusTokens.at(index),
            lmRewards[token].bonusTokenAmounts[lmRewards[token].bonusTokens.at(index)]
        );
    }

    function getNumVestingLMTokenRewards(address user)
        external
        view
        override
        returns (uint256 num)
    {
        return vestingLMTokenRewards[user].length();
    }

    function getVestingLMTokenAt(address user, uint256 index)
        external
        view
        override
        returns (address token)
    {
        return vestingLMTokenRewards[user].at(index);
    }

    function getNumVests(address user, address token) external view override returns (uint256 num) {
        return vestingLMRewards[user][token].length;
    }

    function getLMRewardVestingData(
        address user,
        address token,
        uint256 index
    ) external view override returns (uint256 amount, uint256 startedAt) {
        return (
            vestingLMRewards[user][token][index].amount,
            vestingLMRewards[user][token][index].startedAt
        );
    }

    function getNumRewardCalcTemplates() external view override returns (uint256 num) {
        return rewardCalcTemplateNames.length;
    }

    /* helper functions */

    function isValidVault(address vault, address factory)
        public
        view
        override
        returns (bool validity)
    {
        // validate vault is created from whitelisted vault factory and is an instance of that factory
        return _vaultFactorySet.contains(factory) && IInstanceRegistry(factory).isInstance(vault);
    }

    function isValidAddress(address target) public view override returns (bool validity) {
        // sanity check target for potential input errors
        return
            target != address(this) &&
            target != address(0) &&
            target != rewardToken &&
            target != rewardPool &&
            !_bonusTokenSet.contains(target);
    }

    function _tierMultipliedReward(
        uint256 nftId,
        address nftFactory,
        uint256 reward
    ) private view returns (uint256 multipliedReward) {
        // get tier
        string memory tier = getNftTier(nftId, nftFactory);
        bytes32 tierHash = keccak256(abi.encodePacked(tier));

        if (tierHash == keccak256(abi.encodePacked(PIONNER))) {
            multipliedReward = reward.mul(PIONNER_LM_REWARD_MULTIPLIER_NUM).div(
                PIONNER_LM_REWARD_MULTIPLIER_DENOM
            );
        } else if (tierHash == keccak256(abi.encodePacked(PRECURSOR))) {
            multipliedReward = reward.mul(PRECURSOR_LM_REWARD_MULTIPLIER_NUM).div(
                PRECURSOR_LM_REWARD_MULTIPLIER_DENOM
            );
        } else if (tierHash == keccak256(abi.encodePacked(INNOVATOR))) {
            multipliedReward = reward.mul(INNOVATOR_LM_REWARD_MULTIPLIER_NUM).div(
                INNOVATOR_LM_REWARD_MULTIPLIER_DENOM
            );
        } else if (tierHash == keccak256(abi.encodePacked(EARLY_ADOPTER))) {
            multipliedReward = reward.mul(EARLY_ADOPTER_LM_REWARD_MULTIPLIER_NUM).div(
                EARLY_ADOPTER_LM_REWARD_MULTIPLIER_DENOM
            );
        } else if (tierHash == keccak256(abi.encodePacked(STANDARD))) {
            multipliedReward = reward.mul(STANDARD_LM_REWARD_MULTIPLIER_NUM).div(
                STANDARD_LM_REWARD_MULTIPLIER_DENOM
            );
        }
    }

    /* user functions */

    /// @notice Exit ArbiStaker without claiming reward
    /// @dev This function should never revert when correctly called by the vault.
    ///      A max number of tokens staked per vault is set with MAX_TOKENS_STAKED_PER_VAULT to
    ///      place an upper bound on the for loop.
    /// access control: callable by anyone but fails if caller is not an approved vault
    /// state machine:
    ///   - when vault exists on this ArbiStaker
    ///   - when active stake from this vault
    ///   - any power state
    /// state scope:
    ///   - decrease stakedTokenTotal[token], delete if 0
    ///   - delete _vaults[vault].tokenStake[token]
    ///   - remove _vaults[vault].tokens.remove(token)
    ///   - delete _vaults[vault]
    ///   - remove vault from _vaultSet
    ///   - remove token from _allStakedTokens if required
    /// token transfer: none
    function rageQuit() external override {
        require(_vaultSet.contains(msg.sender), "ArbiStakerERC20: no vault");
        //fetch vault storage reference
        VaultData storage vaultData = _vaults[msg.sender];
        // revert if no active tokens staked
        EnumerableSet.AddressSet storage vaultTokens = vaultData.tokens;
        require(vaultTokens.length() > 0, "ArbiStakerERC20: no stake");

        // update totals
        for (uint256 index = 0; index < vaultTokens.length(); index++) {
            address token = vaultTokens.at(index);
            vaultTokens.remove(token);
            uint256 amount = vaultData.tokenStake[token];
            uint256 newTotal = stakedTokenTotal[token].sub(amount);
            assert(newTotal >= 0);
            if (newTotal == 0) {
                _allStakedTokens.remove(token);
                delete stakedTokenTotal[token];
            } else {
                stakedTokenTotal[token] = newTotal;
            }
            delete vaultData.tokenStake[token];
        }

        // delete vault data
        _vaultSet.remove(msg.sender);
        delete _vaults[msg.sender];

        // emit event
        emit RageQuit(msg.sender);
    }

    /// @notice Stake ERC20 tokens
    /// @dev anyone can stake to any vault if they have valid permission
    /// access control: anyone
    /// state machine:
    ///   - can be called multiple times
    ///   - only online
    ///   - when vault exists on this ArbiStaker
    /// state scope:
    ///   - add token to _vaults[vault].tokens if not already exists
    ///   - increase _vaults[vault].tokenStake[token]
    ///   - add vault to _vaultSet if not already exists
    ///   - add token to _allStakedTokens if not already exists
    ///   - increase stakedTokenTotal[token]
    /// token transfer: transfer staking tokens from msg.sender to vault
    /// @param vault address The address of the vault to stake to
    /// @param vaultFactory address The address of the vault factory which created the vault
    /// @param token address The address of the token being staked
    /// @param amount uint256 The amount of tokens to stake
    function stakeERC20(
        address vault,
        address vaultFactory,
        address token,
        uint256 amount,
        bytes calldata permission
    ) external override onlyOnline {
        // verify vault is valid
        require(isValidVault(vault, vaultFactory), "ArbiStakerERC20: vault is not valid");
        // verify non-zero amount
        require(amount != 0, "ArbiStakerERC20: no amount staked");
        // check sender balance
        require(IERC20(token).balanceOf(msg.sender) >= amount, "insufficient token balance");

        // add vault to set
        _vaultSet.add(vault);
        // fetch vault storage reference
        VaultData storage vaultData = _vaults[vault];

        // verify stakes boundary not reached
        require(
            vaultData.tokens.length() < MAX_TOKENS_STAKED_PER_VAULT,
            "ArbiStakerERC20: MAX_TOKENS_STAKED_PER_VAULT reached"
        );

        // add token to set and increase amount
        vaultData.tokens.add(token);
        vaultData.tokenStake[token] = vaultData.tokenStake[token].add(amount);

        // update total token staked
        _allStakedTokens.add(token);
        stakedTokenTotal[token] = stakedTokenTotal[token].add(amount);

        // perform transfer
        TransferHelper.safeTransferFrom(token, msg.sender, vault, amount);
        // call lock on vault
        IUniversalVault(vault).lockERC20(token, amount, permission);

        // check if there is a reward program currently running
        if (lmRewards[token].startedAt != 0) {
            address rewardCalcInstance = lmRewards[token].rewardCalcInstance;
            (, uint256 rewardEarned, ) =
                IERC2917(rewardCalcInstance).increaseProductivity(msg.sender, amount);
            earnedLMRewards[msg.sender][token] = earnedLMRewards[msg.sender][token].add(
                rewardEarned
            );
        }

        // emit event
        emit Staked(vault, amount);
    }

    /// @notice Unstake ERC20 tokens and claim reward
    /// @dev LM rewards can only be claimed when unstaking
    /// access control: anyone with permission
    /// state machine:
    ///   - when vault exists on this ArbiStakerERC20
    ///   - after stake from vault
    ///   - can be called multiple times while sufficient stake remains
    ///   - only online
    /// state scope:
    ///   - decrease _vaults[vault].tokenStake[token]
    ///   - delete token from _vaults[vault].tokens if token stake is 0
    ///   - decrease stakedTokenTotal[token]
    ///   - delete token from _allStakedTokens if total token stake is 0
    /// token transfer:
    ///   - transfer reward tokens from reward pool to recipient
    ///   - transfer bonus tokens from reward pool to recipient
    /// @param vault address The vault to unstake from
    /// @param vaultFactory address The vault factory that created this vault
    /// @param recipient address The recipient to send reward to
    /// @param token address The staking token
    /// @param amount uint256 The amount of staking tokens to unstake
    /// @param claimBonusReward bool flag to claim bonus rewards
    function unstakeERC20AndClaim(
        address vault,
        address vaultFactory,
        address recipient,
        address token,
        uint256 amount,
        bool claimBonusReward,
        bytes calldata permission
    ) external override onlyOnline {
        require(_vaultSet.contains(vault), "ArbiStakerERC20: no vault");
        // fetch vault storage reference
        VaultData storage vaultData = _vaults[vault];
        // verify non-zero amount
        require(amount != 0, "ArbiStakerERC20: no amount unstaked");
        // validate recipient
        require(isValidAddress(recipient), "ArbiStakerERC20: invalid recipient");
        // check for sufficient vault stake amount
        require(vaultData.tokens.contains(token), "ArbiStakerERC20: no token in vault");
        // check for sufficient vault stake amount
        require(
            vaultData.tokenStake[token] >= amount,
            "ArbiStakerERC20: insufficient vault token stake"
        );
        // check for sufficient total token stake amount
        // if the above check succeeds and this check fails, there is a bug in stake accounting
        require(
            stakedTokenTotal[token] >= amount,
            "stakedTokenTotal[token] is less than amount being unstaked"
        );

        // check if there is a reward program currently running
        uint256 rewardEarned = earnedLMRewards[msg.sender][token];
        if (lmRewards[token].startedAt != 0) {
            address rewardCalcInstance = lmRewards[token].rewardCalcInstance;
            (, uint256 newReward, ) =
                IERC2917(rewardCalcInstance).decreaseProductivity(msg.sender, amount);
            rewardEarned = rewardEarned.add(newReward);
        }

        // decrease vaultTokenStake of token in this vault
        vaultData.tokenStake[token] = vaultData.tokenStake[token].sub(amount);
        if (vaultData.tokenStake[token] == 0) {
            vaultData.tokens.remove(token);
            delete vaultData.tokenStake[token];
        }

        // decrease stakedTokenTotal across all vaults
        stakedTokenTotal[token] = stakedTokenTotal[token].sub(amount);
        if (stakedTokenTotal[token] == 0) {
            _allStakedTokens.remove(token);
            delete stakedTokenTotal[token];
        }

        // unlock staking tokens from vault
        IUniversalVault(vault).unlockERC20(token, amount, permission);

        // emit event
        emit Unstaked(vault, amount);

        // only perform on non-zero reward
        if (rewardEarned > 0) {
            // transfer bonus tokens from reward pool to recipient
            // bonus tokens can only be claimed during an active rewards program
            if (claimBonusReward && lmRewards[token].startedAt != 0) {
                for (uint256 index = 0; index < lmRewards[token].bonusTokens.length(); index++) {
                    // fetch bonus token address reference
                    address bonusToken = lmRewards[token].bonusTokens.at(index);
                    // calculate bonus token amount
                    // bonusAmount = rewardEarned * allocatedBonusReward / allocatedMainReward
                    uint256 bonusAmount =
                        rewardEarned.mul(lmRewards[token].bonusTokenAmounts[bonusToken]).div(
                            lmRewards[token].amount
                        );
                    // transfer bonus token
                    IRewardPool(rewardPool).sendERC20(bonusToken, recipient, bonusAmount);
                    // emit event
                    emit RewardClaimed(vault, recipient, bonusToken, bonusAmount);
                }
            }
            // take care of multiplier
            uint256 multipliedReward =
                _tierMultipliedReward(uint256(vault), vaultFactory, rewardEarned);
            // take care of vesting
            uint256 vestingPortion =
                multipliedReward.mul(LM_REWARD_VESTING_PORTION_NUM).div(
                    LM_REWARD_VESTING_PORTION_DENOM
                );
            vestingLMRewards[msg.sender][token].push(
                LMRewardVestingData(vestingPortion, block.timestamp)
            );
            vestingLMTokenRewards[msg.sender].add(token);
            // set earned reward to 0
            earnedLMRewards[msg.sender][token] = 0;
            // transfer reward tokens from reward pool to recipient
            IRewardPool(rewardPool).sendERC20(
                rewardToken,
                recipient,
                multipliedReward.sub(vestingPortion)
            );
            // emit event
            emit RewardClaimed(vault, recipient, rewardToken, rewardEarned);
        }
    }

    function claimVestedRewardAll() external override onlyOnline {
        uint256 numTokens = vestingLMTokenRewards[msg.sender].length();
        for (uint256 index = 0; index < numTokens; index++) {
            address token = vestingLMTokenRewards[msg.sender].at(index);
            claimVestedReward(token, vestingLMRewards[msg.sender][token].length);
        }
    }

    function claimVestedRewardToken(address token) external override onlyOnline {
        claimVestedReward(token, vestingLMRewards[msg.sender][token].length);
    }

    function claimVestedReward(address token, uint256 numVests) public onlyOnline {
        require(
            numVests <= vestingLMRewards[msg.sender][token].length,
            "num vests can't be greater than available vests"
        );
        LMRewardVestingData[] storage vests = vestingLMRewards[msg.sender][token];
        uint256 vestedReward;
        for (uint256 index = 0; index < numVests; index++) {
            LMRewardVestingData storage vest = vests[index];
            uint256 duration = block.timestamp.sub(vest.startedAt);
            uint256 vested = vest.amount.mul(duration).div(LM_REWARD_VESTING_PERIOD);
            if (vested >= vest.amount) {
                // completely vested
                vested = vest.amount;
                // copy last element into this slot and pop last
                vests[index] = vests[vests.length - 1];
                vests.pop();
                index--;
                numVests--;
                // if all vested remove from set
                if (vests.length == 0) {
                    vestingLMTokenRewards[msg.sender].remove(token);
                    break;
                }
            } else {
                vest.amount = vest.amount.sub(vested);
            }
            vestedReward = vestedReward.add(vested);
        }
        if (vestedReward > 0) {
            // transfer reward tokens from reward pool to recipient
            IRewardPool(rewardPool).sendERC20(rewardToken, msg.sender, vestedReward);
            // emit event
            emit VestedRewardClaimed(msg.sender, rewardToken, vestedReward);
        }
    }
}


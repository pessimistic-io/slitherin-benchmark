//SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC721ReceiverUpgradeable.sol";
import "./StringsUpgradeable.sol";

import "./ISmolRingStaking.sol";
import "./ICreatureOwnerResolverRegistry.sol";
import "./ICreatureOwnerResolver.sol";
import "./ISmolRings.sol";
import "./ISmolMarriage.sol";
import "./ISmolHappiness.sol";
import "./ITokenDistributor.sol";

/**
 * @title  SmolRingStaking contract
 * @author Archethect
 * @notice This contract contains all functionalities for Staking Smol Rings
 */
contract SmolRingStaking is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC721ReceiverUpgradeable,
    ISmolRingStaking
{
    using StringsUpgradeable for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    mapping(address => RewardTokenState) public rewardTokenStateMapping;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public userRewardPerTokenPaid;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public rewardsByAccount;
    mapping(address => mapping(uint256 => uint256)) public lastRewardPayoutTimestamp;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public fidelity;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public claimedFidelity;
    mapping(address => mapping(uint256 => uint256)) public lastClaimedByCreature;

    bool public emergencyShutdown;
    uint256 public totalShare;
    uint256 public fidelityPercentage;
    uint256 public fidelityDenominator;
    address[] public rewardTokens;

    ISmolRings public smolRings;
    ISmolMarriage public smolMarriage;
    ISmolHappiness public smolHappiness;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address smolRings_,
        address smolMarriage_,
        address smolHappiness_,
        address dao_
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        require(smolRings_ != address(0), "ABSTRACTSTAKING:ILLEGAL_ADDRESS");
        require(smolMarriage_ != address(0), "ABSTRACTSTAKING:ILLEGAL_ADDRESS");
        require(smolHappiness_ != address(0), "ABSTRACTSTAKING:ILLEGAL_ADDRESS");
        require(dao_ != address(0), "ABSTRACTSTAKING:ILLEGAL_ADDRESS");
        smolRings = ISmolRings(smolRings_);
        smolMarriage = ISmolMarriage(smolMarriage_);
        smolHappiness = ISmolHappiness(smolHappiness_);
        fidelityPercentage = 3000;
        fidelityDenominator = 10000;
        _setupRole(ADMIN_ROLE, dao_);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(GUARDIAN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, smolMarriage_);
        _setupRole(OPERATOR_ROLE, smolHappiness_);
        _setRoleAdmin(GUARDIAN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    modifier onlyGuardian() {
        require(hasRole(GUARDIAN_ROLE, msg.sender), "ABSTRACTSTAKING:ACCESS_DENIED");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "ABSTRACTSTAKING:ACCESS_DENIED");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "ABSTRACTSTAKING:ACCESS_DENIED");
        _;
    }

    function lastTimeRewardApplicable(address rewardToken) public view returns (uint256) {
        uint256 periodFinish = rewardTokenStateMapping[rewardToken].periodFinish;
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Add new reward token
     * @param reward The amount of tokens to emit over the total reward duration
     * @param tokenDistributor address of contract handling the actual reward emission
     * @param rewardsDuration Duration of the rewards emission
     */
    function addRewardToken(
        uint256 reward,
        address tokenDistributor,
        uint256 rewardsDuration
    ) external onlyAdmin {
        require(
            !rewardTokenStateMapping[tokenDistributor].valid,
            "ABSTRACTSTAKING:TOKEN_ALLREADY_REGISTERED_AS_REWARD_TOKEN"
        );
        require(tokenDistributor != address(0), "ABSTRACTSTAKING:ILLEGAL_ADDRESS");
        rewardTokens.push(tokenDistributor);
        rewardTokenStateMapping[tokenDistributor] = RewardTokenState(
            true,
            (reward / rewardsDuration),
            0,
            block.timestamp,
            rewardsDuration,
            block.timestamp + rewardsDuration,
            tokenDistributor
        );
        emit RewardTokenAdded(reward, tokenDistributor, rewardsDuration);
    }

    /**
     * @notice Update the emission rate of an existing reward token
     * @param tokenDistributor address of contract handling the actual reward emission
     * @param reward reward to be added during the rewardsDuration
     */
    function addRewards(address tokenDistributor, uint256 reward) external onlyAdmin {
        require(
            rewardTokenStateMapping[tokenDistributor].valid,
            "ABSTRACTSTAKING:TOKEN_NOT_REGISTERED_AS_REWARD_TOKEN"
        );
        rewardTokenStateMapping[tokenDistributor].rewardPerTokenStored = rewardPerToken(tokenDistributor);

        rewardTokenStateMapping[tokenDistributor].lastRewardsRateUpdate = lastTimeRewardApplicable(tokenDistributor);

        if (block.timestamp >= rewardTokenStateMapping[tokenDistributor].periodFinish) {
            rewardTokenStateMapping[tokenDistributor].rewardRatePerSecondInBPS =
                reward /
                rewardTokenStateMapping[tokenDistributor].rewardsDuration;
        } else {
            uint256 remaining = rewardTokenStateMapping[tokenDistributor].periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardTokenStateMapping[tokenDistributor].rewardRatePerSecondInBPS;
            rewardTokenStateMapping[tokenDistributor].rewardRatePerSecondInBPS =
                (reward + leftover) /
                rewardTokenStateMapping[tokenDistributor].rewardsDuration;
        }

        rewardTokenStateMapping[tokenDistributor].lastRewardsRateUpdate = block.timestamp;
        rewardTokenStateMapping[tokenDistributor].periodFinish =
            block.timestamp +
            rewardTokenStateMapping[tokenDistributor].rewardsDuration;
        emit RewardAdded(tokenDistributor, reward);
    }

    function setRewardsDuration(address tokenDistributor, uint256 rewardsDuration) external onlyAdmin {
        require(
            rewardTokenStateMapping[tokenDistributor].valid,
            "ABSTRACTSTAKING:TOKEN_NOT_REGISTERED_AS_REWARD_TOKEN"
        );
        require(
            block.timestamp > rewardTokenStateMapping[tokenDistributor].periodFinish,
            "ABSTRACTSTAKING:CURRENT_REWARDS_PERIOD_NOT_FINISHED"
        );
        rewardTokenStateMapping[tokenDistributor].rewardsDuration = rewardsDuration;
        emit RewardsDurationUpdated(tokenDistributor, rewardsDuration);
    }

    function rewardPerToken(address rewardToken) public view returns (uint256) {
        if (rewardTokenStateMapping[rewardToken].valid && totalShare > 0) {
            uint256 delta = lastTimeRewardApplicable(rewardToken) -
                rewardTokenStateMapping[rewardToken].lastRewardsRateUpdate;
            uint256 accruedRewards = (1000 * (delta * rewardTokenStateMapping[rewardToken].rewardRatePerSecondInBPS)) /
                totalShare;
            return (rewardTokenStateMapping[rewardToken].rewardPerTokenStored + accruedRewards);
        }
        return rewardTokenStateMapping[rewardToken].rewardPerTokenStored;
    }

    /**
     * @notice Calculate the current rewards of a Creature.
     * Formula ==> HappinessAdjusted(RewardFactorOfRing1 * newRewards) + HappinessAdjusted(RewardFactorOfRing2 * newRewards)
     * HappinessAdjusted:
     * sum_(n=1)^secondsPassedSinceLastPayout * (newlyAccruedRewards * (startHappiness - HappinessDecay * (n - 1)))
     * / (secondsPassedSinceLastPayout * maxPossibleHappiness)
     * @param creature creature object
     */
    function calculateCurrentRewards(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256[] memory currentRewardsArray = new uint256[](rewardTokens.length);
        uint256[] memory currentRewardsPerTokenArray = new uint256[](rewardTokens.length);
        uint256 currentRewardPerToken;
        uint256 newlyAccruedRewardsPerToken;
        uint256 currentRewards;
        RewardCalculation memory rewardCalculation = getRingDetails(creature);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            currentRewardPerToken = rewardPerToken(rewardTokens[i]);
            newlyAccruedRewardsPerToken =
                currentRewardPerToken -
                userRewardPerTokenPaid[rewardTokens[i]][creature.ownerResolver][creature.tokenId];
            currentRewards =
                rewardsByAccount[rewardTokens[i]][creature.ownerResolver][creature.tokenId] +
                _happinessAdjustedScore(rewardCalculation.rewardFactor1, newlyAccruedRewardsPerToken, creature) +
                _happinessAdjustedScore(rewardCalculation.rewardFactor2, newlyAccruedRewardsPerToken, creature);
            currentRewardsArray[i] = currentRewards;
            currentRewardsPerTokenArray[i] = currentRewardPerToken;
        }
        return (currentRewardsArray, currentRewardsPerTokenArray);
    }

    function _happinessAdjustedScore(
        uint256 rewardFactor,
        uint256 rewardsPerToken,
        ICreatureOwnerResolverRegistry.Creature memory creature
    ) internal view returns (uint256) {
        uint256 secondsPassedSinceLastPayout = lastRewardPayoutTimestamp[creature.ownerResolver][creature.tokenId] == 0
            ? 0
            : block.timestamp - lastRewardPayoutTimestamp[creature.ownerResolver][creature.tokenId];
        if (secondsPassedSinceLastPayout > 0) {
            uint256 startHappiness = smolHappiness.getStartHappiness(creature);
            uint256 happinessDecay = smolHappiness.getHappinessDecayPerSec();
            uint256 numberOfIterations = (happinessDecay > 0 &&
                (startHappiness / happinessDecay) < secondsPassedSinceLastPayout)
                ? (startHappiness / happinessDecay)
                : secondsPassedSinceLastPayout;
            return
                ((rewardFactor *
                    (rewardsPerToken *
                        uint256(
                            2 *
                                int256(numberOfIterations * startHappiness) +
                                int256(numberOfIterations) *
                                (int256(happinessDecay) - int256(numberOfIterations * happinessDecay))
                        ))) / (2 * smolHappiness.getMaxHappiness() * secondsPassedSinceLastPayout)) / 1000;
        }
        return 0;
    }

    function _accrueRewards(ICreatureOwnerResolverRegistry.Creature memory creature, bool persist)
        internal
        returns (uint256[] memory)
    {
        (uint256[] memory currentRewards, uint256[] memory currentRewardPerToken) = calculateCurrentRewards(creature);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            rewardTokenStateMapping[rewardTokens[i]].rewardPerTokenStored = rewardPerToken(rewardTokens[i]);
            rewardTokenStateMapping[rewardTokens[i]].lastRewardsRateUpdate = block.timestamp;
            rewardsByAccount[rewardTokens[i]][creature.ownerResolver][creature.tokenId] = currentRewards[i];
            userRewardPerTokenPaid[rewardTokens[i]][creature.ownerResolver][creature.tokenId] = currentRewardPerToken[
                i
            ];
        }
        lastRewardPayoutTimestamp[creature.ownerResolver][creature.tokenId] = block.timestamp;
        if (persist) {
            smolHappiness.setHappiness(creature, smolHappiness.getCurrentHappiness(creature));
        }
        return currentRewards;
    }

    function _stake(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 ring) internal {
        require(!emergencyShutdown, "ABSTRACTSTAKING:SHUTDOWN");
        require(!smolMarriage.isMarried(creature), "ABSTRACTSTAKING:STAKING_MARRIED_CREATURE");
        uint256[] memory rewards = _accrueRewards(creature, true);
        //Take double amounts into account because of emissions going to both parties
        totalShare += smolRings.ringRarity(ring) * 2;
        emit Staked(creature, rewards);
    }

    function _unstake(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 ring) internal {
        if (emergencyShutdown) return;
        require(smolMarriage.isMarried(creature), "ABSTRACTSTAKING:UNSTAKING_UNMARRIED_CREATURE");
        uint256[] memory rewards = _accrueRewards(creature, true);
        //Take double amounts into account because of emissions going to both parties
        totalShare -= smolRings.ringRarity(ring) * 2;
        emit Unstaked(creature, rewards);
    }

    /**
     * @notice Claim the rewards of a an array of Creatures
     * @param creatures creature object
     */
    function claim(ICreatureOwnerResolverRegistry.Creature[] memory creatures) external nonReentrant {
        require(!emergencyShutdown, "ABSTRACTSTAKING:SHUTDOWN");
        for (uint256 i = 0; i < creatures.length; i++) {
            require(isOwner(msg.sender, creatures[i]), "ABSTRACTSTAKING:NOT_OWNER_OF_CREATURE");
            (uint256[] memory currentRewards, uint256[] memory currentRewardPerToken) = calculateCurrentRewards(
                creatures[i]
            );
            for (uint256 j = 0; j < rewardTokens.length; j++) {
                if (currentRewards[j] > 0) {
                    uint256 currentFidelityFee = ((currentRewards[j] * fidelityPercentage) / fidelityDenominator);
                    uint256 claimedFidelityFee = claimedFidelity[creatures[i].ownerResolver][creatures[i].tokenId][j];
                    claimedFidelity[creatures[i].ownerResolver][creatures[i].tokenId][j] = 0;
                    fidelity[creatures[i].ownerResolver][creatures[i].tokenId][j] =
                        fidelity[creatures[i].ownerResolver][creatures[i].tokenId][j] +
                        currentFidelityFee -
                        claimedFidelityFee;
                    rewardsByAccount[rewardTokens[j]][creatures[i].ownerResolver][creatures[i].tokenId] = 0;
                    userRewardPerTokenPaid[rewardTokens[j]][creatures[i].ownerResolver][
                        creatures[i].tokenId
                    ] = currentRewardPerToken[j];
                    ITokenDistributor(rewardTokenStateMapping[rewardTokens[j]].tokenDistributor).payout(
                        msg.sender,
                        currentRewards[j] - currentFidelityFee
                    );
                }
            }
            lastRewardPayoutTimestamp[creatures[i].ownerResolver][creatures[i].tokenId] = block.timestamp;
            smolHappiness.setHappiness(creatures[i], smolHappiness.getCurrentHappiness(creatures[i]));
            emit Rewarded(creatures[i], currentRewards);
        }
    }

    function claimFidelity(ICreatureOwnerResolverRegistry.Creature[] memory creatures, address account)
        public
        onlyOperator
        nonReentrant
    {
        require(!emergencyShutdown, "ABSTRACTSTAKING:SHUTDOWN");
        for (uint256 i = 0; i < creatures.length; i++) {
            require(isOwner(account, creatures[i]), "ABSTRACTSTAKING:NOT_OWNER_OF_CREATURE");
            require(hasFidelity(creatures[i]), "ABSTRACTSTAKING:NO_FIDELITY_AMOUNT_AVAILABLE");
            _accrueRewards(creatures[i], true);
            uint256[] memory toClaim = claimableFidelityOf(creatures[i]);
            for (uint256 j = 0; j < rewardTokens.length; j++) {
                if (toClaim[i] > 0) {
                    ITokenDistributor(rewardTokenStateMapping[rewardTokens[j]].tokenDistributor).payout(
                        account,
                        toClaim[j]
                    );
                    fidelity[creatures[i].ownerResolver][creatures[i].tokenId][j] = 0;
                    claimedFidelity[creatures[i].ownerResolver][creatures[i].tokenId][j] =
                        claimedFidelity[creatures[i].ownerResolver][creatures[i].tokenId][j] +
                        toClaim[j];
                }
            }
        }
    }

    function hasFidelity(ICreatureOwnerResolverRegistry.Creature memory creature) public view returns (bool) {
        uint256[] memory fidelityMap = claimableFidelityOf(creature);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (fidelityMap[i] > 0) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Return claimable rewards of a Creature
     * @param creature creature object
     */
    function claimableOf(ICreatureOwnerResolverRegistry.Creature memory creature)
        external
        view
        returns (uint256[] memory)
    {
        (uint256[] memory currentRewards, ) = calculateCurrentRewards(creature);
        uint256[] memory correctedRewards = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (currentRewards[i] > 0) {
                uint256 currentFidelityFee = ((currentRewards[i] * fidelityPercentage) / fidelityDenominator);
                correctedRewards[i] = currentRewards[i] - currentFidelityFee;
            }
        }
        return correctedRewards;
    }

    /**
     * @notice Return claimable fidelity of a Creature
     * @param creature creature object
     */
    function claimableFidelityOf(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (uint256[] memory)
    {
        (uint256[] memory currentRewards, ) = calculateCurrentRewards(creature);
        uint256[] memory fidelityRewards = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 currentFidelityFee = 0;
            if (currentRewards[i] > 0) {
                currentFidelityFee = ((currentRewards[i] * fidelityPercentage) / fidelityDenominator);
            }
            fidelityRewards[i] =
                currentFidelityFee +
                fidelity[creature.ownerResolver][creature.tokenId][i] -
                claimedFidelity[creature.ownerResolver][creature.tokenId][i];
        }
        return fidelityRewards;
    }

    function setEmergencyShutdown(bool emergencyShutdown_) external onlyGuardian {
        emergencyShutdown = emergencyShutdown_;
    }

    function isOwner(address account, ICreatureOwnerResolverRegistry.Creature memory creature)
        internal
        view
        returns (bool)
    {
        if (ICreatureOwnerResolver(creature.ownerResolver).isOwner(account, creature.tokenId)) {
            return true;
        }
        return false;
    }

    function getRingDetails(ICreatureOwnerResolverRegistry.Creature memory creature)
        internal
        view
        returns (RewardCalculation memory)
    {
        if (smolMarriage.isMarried(creature)) {
            ISmolMarriage.Marriage memory marriage = smolMarriage.getMarriage(creature);
            return
                RewardCalculation(
                    smolRings.ringRarity(marriage.ring1),
                    smolRings.ringRarity(marriage.ring2),
                    smolRings.getRingProps(marriage.ring1).ringType,
                    smolRings.getRingProps(marriage.ring2).ringType
                );
        } else {
            return RewardCalculation(0, 0, 0, 0);
        }
    }

    function setFidelityPercentage(uint256 fidelityPercentage_) external onlyAdmin {
        fidelityPercentage = fidelityPercentage_;
    }

    /**
     * @notice Stake rings to ge marriage rewards
     * @param ring1 id of ring 1
     * @param creature1 creature object 1
     * @param ring2 id of ring 2
     * @param creature2 creature object 2
     */
    function stake(
        uint256 ring1,
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        uint256 ring2,
        ICreatureOwnerResolverRegistry.Creature memory creature2,
        address ownerCreature1,
        address ownerCreature2
    ) public nonReentrant onlyOperator {
        require(isOwner(ownerCreature1, creature1), "ABSTRACTSTAKING:NOT_OWNER_OF_CREATURE");
        require(isOwner(ownerCreature2, creature2), "ABSTRACTSTAKING:NOT_OWNER_OF_CREATURE");
        smolRings.safeTransferFrom(ownerCreature1, address(this), ring1);
        smolRings.safeTransferFrom(ownerCreature2, address(this), ring2);
        _stake(creature1, ring1);
        _stake(creature2, ring2);
    }

    /**
     * @notice Unstake rings on divorce
     * @param ring1 ring of divorce initiator
     * @param ring2 ring of other party
     * @param creature1 creature object 1
     * @param creature2 creature object 2
     */
    function unstake(
        uint256 ring1,
        uint256 ring2,
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2,
        address ownerCreature1
    ) public nonReentrant onlyOperator {
        require(isOwner(ownerCreature1, creature1), "ABSTRACTSTAKING:NOT_OWNER_OF_CREATURE");
        _unstake(creature1, ring1);
        _unstake(creature2, ring2);
        smolRings.safeTransferFrom(address(this), ownerCreature1, ring1);
    }

    /**
     * @notice Withdraw ring (used by ex-partner of divorce initiator)
     * @param ring of ex-partner
     * @param creature creature object
     */
    function withdrawRing(
        uint256 ring,
        ICreatureOwnerResolverRegistry.Creature memory creature,
        address ownerCreature
    ) public nonReentrant onlyOperator {
        require(isOwner(ownerCreature, creature), "ABSTRACTSTAKING:NOT_OWNER_OF_CREATURE");
        smolRings.safeTransferFrom(address(this), ownerCreature, ring);
    }

    /**
     * @notice Accrue rewards for creature
     * @param creature creature object
     */
    function accrueForNewScore(ICreatureOwnerResolverRegistry.Creature memory creature) public onlyOperator {
        _accrueRewards(creature, false);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure override returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}


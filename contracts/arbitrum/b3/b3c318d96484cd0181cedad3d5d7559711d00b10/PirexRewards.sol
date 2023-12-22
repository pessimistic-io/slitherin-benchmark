// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ERC20} from "./ERC20.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {IPirexGmx} from "./IPirexGmx.sol";

/**
    Originally inspired by and utilizes Fei Protocol's Flywheel V2 accrual logic
    (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract PirexRewards is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using FixedPointMathLib for uint256;

    struct User {
        // User indexes by strategy
        mapping(bytes => uint256) index;
        // Accrued but not yet transferred rewards
        mapping(ERC20 => uint256) rewardsAccrued;
        // Accounts which users are forwarding their rewards to
        mapping(ERC20 => address) rewardRecipients;
    }

    // The fixed point factor
    uint256 public constant ONE = 1e18;

    // Core reward-producing Pirex contract
    IPirexGmx public producer;

    // Strategies by producer token
    mapping(ERC20 => bytes[]) public strategies;

    // Strategy indexes
    mapping(bytes => uint256) public strategyIndexes;

    // User data
    mapping(address => User) internal users;

    event SetProducer(address producer);
    event AddStrategy(bytes indexed newStrategy);
    event Claim(
        ERC20 indexed rewardToken,
        address indexed user,
        address indexed recipient,
        uint256 amount
    );
    event SetRewardRecipient(
        address indexed user,
        ERC20 indexed rewardToken,
        address indexed recipient
    );
    event UnsetRewardRecipient(address indexed user, ERC20 indexed rewardToken);
    event AccrueStrategy(
        ERC20[] producerTokens,
        ERC20[] rewardTokens,
        uint256[] rewardAmounts
    );
    event AccrueUser(
        ERC20 indexed producerToken,
        address indexed user,
        bytes[] strategy
    );

    error StrategyAlreadySet();
    error ZeroAddress();
    error EmptyArray();
    error NotContract();

    constructor() {
        // Best practice to prevent the implementation contract from being initialized
        _disableInitializers();
    }

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
    }

    /**
        @notice Get strategies for a producer token
        @param  producerToken  ERC20    Producer token contract
        @return                bytes[]  Strategies list
     */
    function getStrategies(ERC20 producerToken)
        external
        view
        returns (bytes[] memory)
    {
        return strategies[producerToken];
    }

    /**
        @notice Get a strategy index for a user
        @param  user      address  User
        @param  strategy  bytes    Strategy (abi-encoded producer and reward tokens)
     */
    function getUserIndex(address user, bytes memory strategy)
        external
        view
        returns (uint256)
    {
        return users[user].index[strategy];
    }

    /**
        @notice Get the rewards accrued for a user
        @param  user         address  User
        @param  rewardToken  ERC20    Reward token contract
     */
    function getUserRewardsAccrued(address user, ERC20 rewardToken)
        external
        view
        returns (uint256)
    {
        return users[user].rewardsAccrued[rewardToken];
    }

    /**
        @notice Set producer
        @param  _producer  address  Producer contract address
     */
    function setProducer(address _producer) external onlyOwner {
        if (_producer == address(0)) revert ZeroAddress();

        producer = IPirexGmx(_producer);

        emit SetProducer(_producer);
    }

    /**
        @notice Add a strategy comprised of a producer and reward token
        @param  producerToken  ERC20  Producer token contract
        @param  rewardToken    ERC20  Reward token contract
        @return strategy       bytes  Strategy
    */
    function addStrategyForRewards(ERC20 producerToken, ERC20 rewardToken)
        external
        onlyOwner
        returns (bytes memory)
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        bytes memory strategy = abi.encode(producerToken, rewardToken);

        if (strategyIndexes[strategy] != 0) revert StrategyAlreadySet();

        strategies[producerToken].push(strategy);

        strategyIndexes[strategy] = ONE;

        emit AddStrategy(strategy);

        return strategy;
    }

    /**
        @notice Accrue strategy rewards
        @return producerTokens  ERC20[]    Producer token contracts
        @return rewardTokens    ERC20[]    Reward token contracts
        @return rewardAmounts   uint256[]  Reward token amounts
    */
    function accrueStrategy()
        public
        returns (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        // pxGMX and pxGLP rewards must be claimed all at once since PirexGmx is
        // the sole token holder
        (producerTokens, rewardTokens, rewardAmounts) = producer.claimRewards();

        uint256 pLen = producerTokens.length;

        // Iterate over the producer tokens and accrue their strategies
        for (uint256 i; i < pLen; ) {
            uint256 accruedRewards = rewardAmounts[i];

            // Only run strategy accrual logic if there are rewards
            if (accruedRewards != 0) {
                ERC20 producerToken = producerTokens[i];

                // Accumulate rewards per token onto the index, multiplied by fixed-point factor
                strategyIndexes[
                    // Get the strategy (mapping key) by encoding the producer and reward tokens
                    abi.encode(producerToken, rewardTokens[i])
                ] += accruedRewards.mulDivDown(
                    ONE,
                    producerToken.totalSupply()
                );
            }

            // Not possible to overflow since `i` is bound by the length of `producerTokens`
            unchecked {
                ++i;
            }
        }

        emit AccrueStrategy(producerTokens, rewardTokens, rewardAmounts);
    }

    /**
        @notice Accrue user rewards for a producer token's strategies
        @param  producerToken  ERC20    Producer token contract
        @param  user           address  User
    */
    function accrueUser(ERC20 producerToken, address user) public {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (user == address(0)) revert ZeroAddress();

        bytes[] memory s = strategies[producerToken];
        uint256 sLen = s.length;

        if (sLen == 0) revert EmptyArray();

        User storage u = users[user];
        uint256 producerTokenBalance = producerToken.balanceOf(user);

        // Accrue user rewards for each strategy (producer and reward token pair)
        for (uint256 i; i < sLen; ) {
            bytes memory strategy = s[i];

            // Load indices
            uint256 strategyIndex = strategyIndexes[strategy];
            uint256 supplierIndex = u.index[strategy];

            // Sync user index to global
            u.index[strategy] = strategyIndex;

            // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
            // Zero balances will have no effect other than syncing to global index
            if (supplierIndex == 0) {
                supplierIndex = ONE;
            }

            (, ERC20 rewardToken) = abi.decode(strategy, (ERC20, ERC20));

            // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
            u.rewardsAccrued[rewardToken] += producerTokenBalance.mulDivDown(
                strategyIndex - supplierIndex,
                ONE
            );

            // Not possible to overflow since `i` is bound by the length of the producer token's stored strategies
            unchecked {
                ++i;
            }
        }

        emit AccrueUser(producerToken, user, s);
    }

    /**
      @notice Claim rewards for a given user
      @param  rewardTokens  ERC20[]    Reward token contracts
      @param  user          address    The user claiming rewards
      @return claimed       uint256[]  Claimed rewards
    */
    function _claim(ERC20[] memory rewardTokens, address user)
        private
        returns (
            uint256[] memory claimed,
            uint256[] memory postFeeAmounts,
            uint256[] memory feeAmounts
        )
    {
        uint256 rLen = rewardTokens.length;
        User storage u = users[user];
        claimed = new uint256[](rLen);
        postFeeAmounts = new uint256[](rLen);
        feeAmounts = new uint256[](rLen);

        for (uint256 i; i < rLen; ) {
            ERC20 r = rewardTokens[i];
            claimed[i] = u.rewardsAccrued[r];

            if (claimed[i] != 0) {
                u.rewardsAccrued[r] = 0;

                // Forward rewards if a rewardRecipient is set
                address rewardRecipient = u.rewardRecipients[r];
                address recipient = rewardRecipient == address(0)
                    ? user
                    : rewardRecipient;

                (uint256 postFeeAmount, uint256 feeAmount) = producer
                    .claimUserReward(address(r), claimed[i], recipient);
                postFeeAmounts[i] = postFeeAmount;
                feeAmounts[i] = feeAmount;

                emit Claim(r, user, recipient, claimed[i]);
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
      @notice Claim rewards for a given user
      @param  rewardTokens  ERC20[]    Reward token contracts
      @param  user          address    The user claiming rewards
      @return               uint256[]  Claimed rewards
    */
    function claim(ERC20[] memory rewardTokens, address user)
        external
        nonReentrant
        returns (
            uint256[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        if (rewardTokens.length == 0) revert EmptyArray();
        if (user == address(0)) revert ZeroAddress();

        return _claim(rewardTokens, user);
    }

    /**
      @notice Accrue rewards and claim them for a given user
      @param  user            address    The user claiming rewards
      @return producerTokens  ERC20[]    Producer token contracts
      @return rewardTokens    ERC20[]    Reward token contracts
      @return rewardAmounts   uint256[]  Reward token amounts
      @return claimed         uint256[]  Claimed rewards
    */
    function accrueAndClaim(address user)
        external
        nonReentrant
        returns (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts,
            uint256[] memory claimed,
            uint256[] memory postFeeAmounts,
            uint256[] memory feeAmounts
        )
    {
        if (user == address(0)) revert ZeroAddress();

        // Harvest and accrue strategy indexes to ensure the rewards are up-to-date
        (producerTokens, rewardTokens, rewardAmounts) = accrueStrategy();

        uint256 pLen = producerTokens.length;

        for (uint256 i; i < pLen; ) {
            // Accrue rewards for every producer token in preparation for the claim
            accrueUser(producerTokens[i], user);

            unchecked {
                ++i;
            }
        }

        // Claim the producer token's reward tokens
        (claimed, postFeeAmounts, feeAmounts) = _claim(rewardTokens, user);
    }

    /**
        @notice Get the reward recipient for a user by producer and reward token
        @param  user         address  User
        @param  rewardToken  ERC20    Reward token contract
        @return              address  Reward recipient
    */
    function getRewardRecipient(address user, ERC20 rewardToken)
        external
        view
        returns (address)
    {
        return users[user].rewardRecipients[rewardToken];
    }

    /**
        @notice Set reward recipient for a reward token
        @param  rewardToken  ERC20    Reward token contract
        @param  recipient    address  Rewards recipient
    */
    function setRewardRecipient(ERC20 rewardToken, address recipient) external {
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        users[msg.sender].rewardRecipients[rewardToken] = recipient;

        emit SetRewardRecipient(msg.sender, rewardToken, recipient);
    }

    /**
        @notice Unset reward recipient for a reward token
        @param  rewardToken  ERC20  Reward token contract
    */
    function unsetRewardRecipient(ERC20 rewardToken) external {
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        delete users[msg.sender].rewardRecipients[rewardToken];

        emit UnsetRewardRecipient(msg.sender, rewardToken);
    }

    /*//////////////////////////////////////////////////////////////
                    ⚠️ NOTABLE PRIVILEGED METHODS ⚠️
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Privileged method for setting the reward recipient of a contract
        @notice This should ONLY be used to forward rewards for Pirex-GMX LP contracts
        @notice In production, we will have a 2nd multisig which reduces risk of abuse
        @param  lpContract   address  Pirex-GMX LP contract
        @param  rewardToken  ERC20    Reward token contract
        @param  recipient    address  Rewards recipient
    */
    function setRewardRecipientPrivileged(
        address lpContract,
        ERC20 rewardToken,
        address recipient
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        users[lpContract].rewardRecipients[rewardToken] = recipient;

        emit SetRewardRecipient(lpContract, rewardToken, recipient);
    }

    /**
        @notice Privileged method for unsetting the reward recipient of a contract
        @param  lpContract   address  Pirex-GMX LP contract
        @param  rewardToken  ERC20    Reward token contract
    */
    function unsetRewardRecipientPrivileged(
        address lpContract,
        ERC20 rewardToken
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        delete users[lpContract].rewardRecipients[rewardToken];

        emit UnsetRewardRecipient(lpContract, rewardToken);
    }

    // Storage gaps for reserving storage slots for future upgrades
    uint256[10000] private __gap;
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LockBox.sol";
import "./IRewardHandler.sol";
import "./IERC20.sol";
// For debugging only



/**
 * @title Reward Handler
 * @author Deepp Dev Team
 * @notice This is a handler for keeping track of reward distribution.
 * @notice Tokens are locked here until distributed to users. Distribution is
 *         based on distribution token ownership.
 * @notice The locked rewards tokens can be retrieved by users.
 * @notice Add/claim rewards is restricted by TokenValidator.
 * @notice LockBox is TokenValidator is Accesshandler is Initializable.
 */
contract RewardHandler is LockBox, IRewardHandler {

    uint256 private constant FRACTION_PRECISSION = 1e18;

    // Below is used for keeping account of users rewards
    // The common total accumulation of Rewards Per Token (RPT),
    // stored multiplied by FRACTION_PRECISSION to avoid floats.
    // Token => amount
    mapping(address => uint256) public cumulativeRPT;
    // Rewards added while the dist token supply is 0, cannot be distributed.
    // Token => amount
    mapping(address => uint256) public nonDistRewards;
    // Assigned but still unclaimed rewards for a user.
    // Token => user => amount
    mapping(address => mapping(address => uint256)) public claimableRewards;
    // The balance for when rewards per token were last assigned, for a user,
    // stored multiplied by FRACTION_PRECISSION to avoid floats.
    // Token => user => amount
    mapping(address => mapping(address => uint256)) public assignedCumuRPT;

    // Below is only used for debug and info
    // The common total accumulation of rewards
    // Token => amount
    mapping(address => uint256) public cumulativeRewards;
    // The total balance of assigned rewards (including claimed), per user.
    // Token => user => amount
    mapping(address => mapping(address => uint256)) public cumulatedRewards;
    // The total balance of contributed rewards, per user.
    // Token => user => amount
    mapping(address => mapping(address => uint256)) public contributedRewards;
    // Claimed rewards per user.
    // Token => user => amount
    mapping(address => mapping(address => uint256)) public claimedRewards;

    /**
     * Event that fires when rewards are added.
     * @param contributor is the address that generated the reward.
     * @param token is the token contract address
     * @param addedAmount is the amount added.
     */
    event RewardsAdded(
        address indexed contributor,
        address indexed token,
        uint256 addedAmount
    );

    /**
     * Event that fires when rewards are claimed.
     * @param receiver is the address that got the reward tokens.
     * @param token is the token contract address
     * @param claimedAmount is the amount claimed.
     */
    event RewardsClaimed(
        address indexed receiver,
        address indexed token,
        uint256 claimedAmount
    );

    constructor() LockBox() {}

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inDistToken The address of the token used to distribute rewards.
     * @param inRewardToken The address of the token used as reward.
     */
    function init(address inDistToken, address inRewardToken)
        external
        notInitialized
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _addTokenPair(inRewardToken, inDistToken);

        // Init LockBox
        _init();
    }

    /**
     * @notice Claims the rewards of an account, after updating count.
     * @param account is the account, to claim the reward for.
     * @param tokenAdd is the address of the token type.
     */
    function claimRewardsOfAccount(address account, address tokenAdd)
        external
        override
        isInitialized
        whenNotPaused
        onlyRole(REWARD_ADMIN_ROLE)
        onlyAllowedToken(tokenAdd)
    {
        if (address(account) == address(0))
            return;
        _updateClaimableRewards(account, tokenAdd);
        _claim(account, tokenAdd);
    }

    /**
     * @notice Claims the rewards of the caller, after updating count.
     * @param tokenAdd is the address of the token type.
     */
    function claimRewards(address tokenAdd)
        external
        override
        isInitialized
        whenNotPaused
        onlyAllowedToken(tokenAdd)
    {
        _updateClaimableRewards(msg.sender, tokenAdd);
        _claim(msg.sender, tokenAdd);
    }

    /**
     * @notice Updates the common accumulation of rewards.
     * @param contributor is the account, who generated the reward.
     * @param tokenAdd is the address of the token type.
     * @param amount is the amount of tokens added.
     */
    function addRewards(
        address contributor,
        address tokenAdd,
        uint256 amount
    )
        external
        override
        isInitialized
        onlyRole(REWARDER_ROLE)
        onlyAllowedToken(tokenAdd)
    {
        if (amount > 0) {
            address distToken = allowedTokens[tokenAdd];
            cumulativeRewards[tokenAdd] += amount;
            uint256 supply = IERC20(distToken).totalSupply();
            // RPT is multiplied by FRACTION_PRECISSION to avoid floats.
            if (supply > 0) {
                cumulativeRPT[tokenAdd] += amount * FRACTION_PRECISSION / supply;
            } else {
                nonDistRewards[tokenAdd] += amount;
            }
            _lock(address(this), tokenAdd, amount);
            contributedRewards[tokenAdd][contributor] += amount;
            emit RewardsAdded(contributor, tokenAdd, amount);
        }
    }

    /**
     * @notice Updates the assigned rewards for a specific account.
     * @param account The account to update assigned rewards for.
     * @param distTokenAdd is the token that distributes the rewards.
     */
    function updateRewards(address account, address distTokenAdd)
        external
        override
        isInitialized
        whenNotPaused
        onlyAllowedValueToken(distTokenAdd)
    {
        if (address(account) == address(0))
            return;
        _updateClaimableRewards(account, reversedTokens[distTokenAdd]);
    }

    /**
     * @notice Transfers rewards that cannot be distributed to an account.
     * @param account The account to transfer the rewards to.
     * @param tokenAdd is the address of the token type.
     */
    function transferNondistributableRewardsTo(
        address account,
        address tokenAdd
    )
        external
        override
        isInitialized
        onlyRole(REWARD_ADMIN_ROLE)
    {
        if (address(account) == address(0))
            return;

        uint256 amount = nonDistRewards[tokenAdd];
        if (amount == 0)
            return;

        nonDistRewards[tokenAdd] = 0;
        _unlock(address(this), tokenAdd, amount);
        IERC20(tokenAdd).transfer(account, amount);
    }

    /**
     * @notice Returns the amount of available rewards for an account.
     * @param account The account to investigate.
     * @param tokenAdd is the address of the token type.
     */
    function getAvailableRewards(address account, address tokenAdd)
        external
        view
        override
        isInitialized
        onlyAllowedToken(tokenAdd)
        returns(uint256 amount)
    {
        if (address(account) == address(0))
            return 0;
        amount = claimableRewards[tokenAdd][account];
        uint256 _cumulativeRewardsPerToken = cumulativeRPT[tokenAdd];

        // Acc rewards can only increase. If _cumulativeRewardsPerToken
        // is zero, it means there are no rewards yet.
        if (_cumulativeRewardsPerToken == 0) {
            return 0;
        }

        uint256 assigned = assignedCumuRPT[tokenAdd][account];
        uint256 added =_cumulativeRewardsPerToken - assigned;
        // Check if there is new unassigned rewards
        if (added > 0) {
            uint256 distBalance = IERC20(allowedTokens[tokenAdd]).balanceOf(account);
            if (distBalance > 0) {
                // When multiplying the tokens and added rpt,
                // we no longer need the extra precission
                amount += distBalance * added / FRACTION_PRECISSION;
            }
        }
    }

    /**
     * @notice Returns the matching dist token for a reward token type.
     * @param tokenAdd is the address of the token type.
     */
    function getDistToken(address tokenAdd)
        external
        view
        override
        returns(address)
    {
        return allowedTokens[tokenAdd];
    }

    /**
     * @notice Claims the assigned rewards for a specific account.
     * @param account The account to claim assigned rewards for.
     * @param tokenAdd is the address of the token type.
     */
    function _claim(address account, address tokenAdd) private {
        uint256 amount = claimableRewards[tokenAdd][account];
        if (amount > 0) {
            claimableRewards[tokenAdd][account] = 0;
            _unlock(address(this), tokenAdd, amount);
            claimedRewards[tokenAdd][account] += amount;
            IERC20(tokenAdd).transfer(account, amount);
        }
        emit RewardsClaimed(account, tokenAdd, amount);
    }

    /**
     * @notice Updates the assigned rewards for a specific account.
     * @param account The account to update assigned rewards for.
     * @param tokenAdd is the address of the token type.
     */
    function _updateClaimableRewards(address account, address tokenAdd)
         private
    {
        uint256 _cumulativeRPT = cumulativeRPT[tokenAdd];

        // Acc rewards can only increase. If _cumulativeRPT is zero,
        // it means there are no rewards yet.
        if (_cumulativeRPT == 0) {
            return;
        }

        uint256 assigned = assignedCumuRPT[tokenAdd][account];
        uint256 added =_cumulativeRPT - assigned;
        if (added > 0) {
            address distToken = allowedTokens[tokenAdd];
            uint256 distBalance = IERC20(distToken).balanceOf(account);
            if (distBalance > 0) {
                // When multiplying the tokens and added rpt,
                // we no longer need the extra precission
                uint256 addedAccountReward = distBalance * added / FRACTION_PRECISSION;
                if (addedAccountReward > 0) {
                    claimableRewards[tokenAdd][account] += addedAccountReward;
                    cumulatedRewards[tokenAdd][account] += addedAccountReward;
                }
            }
            assignedCumuRPT[tokenAdd][account] = _cumulativeRPT;
        }
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LockBox.sol";
import "./IDaoMain.sol";
import "./TokenAmountValidator.sol";
// For debugging only



/**
 * @title Dao Main
 * @author Deepp Dev Team
 * @notice This is the DAO main, that offers stake func. It is designed to operate
 *         on a single pair of staked/value tokens only, set at init.
 * @notice DAO Tokens are staked by users that receives Staked DAO Tokens.
 * @notice When Staking DAO Tokens, they are put in the internal Lockbox
 *         and SDTs are minted as proof-of-stake.
 * @notice The staked tokens can be retrieved, by swapping the received
 *         holder tokens back.
 * @notice DaoMain is LockBox.
 * @notice LockBox is TokenValidator is Accesshandler is Initializable.
 *
 */
contract DaoMain is LockBox, IDaoMain {

    using TokenAmountValidator for address;

    address private stakedToken; // ILPToken/DistToken
    address private daoToken; // IGovToken
    ITokenTransferProxy private tokenTransferProxy;
    IRewardHandler private rewardHandler1; // Bet rewards for SDT holders
    IRewardHandler private rewardHandler2; // LP rewards for SDT holders

    /**
     * Event that fires when tokens are staked.
     * @param owner is the address that staked tokens.
     * @param tokenAdd is the token contract address.
     * @param amount is the amount staked.
     */
    event TokensStaked(
        address indexed owner,
        address tokenAdd,
        uint256 amount
    );

    /**
     * Event that fires when tokens are unstaked.
     * @param owner is the address that unstaked tokens.
     * @param tokenAdd is the staked-token contract address.
     * @param amount is the amount unstaked.
     */
    event TokensUnstaked(
        address indexed owner,
        address tokenAdd,
        uint256 amount
    );

    /**
     * @notice Event fires when stake of 0 tokens is attempted.
     * @param owner is the owner of the tokens.
     * @param tokenAdd is the token contract address.
     */
    event StakedZero(address indexed owner, address tokenAdd);

    /**
     * @notice Event fires when unstake of 0 tokens is attempted.
     * @param owner is the owner of the staked-tokens.
     * @param tokenAdd is the staked-token contract address.
     */
    event UnstakedZero(address indexed owner, address tokenAdd);

    /**
     * @notice Error for Insufficient user balance for staking/unstaking.
     *         Needed `required` but only `available` available.
     * @param available balance available.
     * @param required requested amount to stake/unstake.
     */
    error InsufficientBalance(uint256 available, uint256 required);

    /**
     * @notice Error for Insufficient allowance for staking/unstaking tokens.
     *         Needed `required` but only `available` available.
     * @param available allowance available.
     * @param required requested amount to stake/unstake.
     */
    error InsufficientAllowance(uint256 available, uint256 required);

    constructor() LockBox() {}

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inStakedToken The Token used to keep the stake balance.
     * @param inTokenTransferProxy The TokenTransferProxy contract address.
     * @param inRewardHandler1 Is 1st contract that handles SDT rewards.
     * @param inRewardHandler2 Is 2nd contract that handles SDT rewards.
     */
    function init(
        ILPToken inStakedToken, // Staked DAO Tokens are LPToken
        ITokenTransferProxy inTokenTransferProxy,
        IRewardHandler inRewardHandler1,
        IRewardHandler inRewardHandler2
    )
        external
        notInitialized
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        stakedToken = address(inStakedToken);
        daoToken = inStakedToken.tokenAdd();

        tokenTransferProxy = inTokenTransferProxy;
        rewardHandler1 = inRewardHandler1;
        rewardHandler2 = inRewardHandler2;

        //Add the dao tokens to the accepted tokens list
        _addTokenPair(daoToken, stakedToken);

        BaseInitializer.initialize();
    }

    /**
     * @notice Setter to change the referenced TokenTransferProxy contract.
     * @param inTokenTransferProxy The TokenTransferProxy contract address.
     */
    function setTokenTransferProxy(ITokenTransferProxy inTokenTransferProxy)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        tokenTransferProxy = inTokenTransferProxy;
    }

    /**
     * @notice Setter to change the referenced rewardHandler1 contract.
     * @param inRewardHandler1 Is 1st contract that handles SDT rewards.
     */
    function setRewardHandler1(IRewardHandler inRewardHandler1)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rewardHandler1 = inRewardHandler1;
    }

    /**
     * @notice Setter to change the referenced rewardHandler2 contract.
     * @param inRewardHandler2 Is 2nd contract that handles SDT rewards.
     */
    function setRewardHandler2(IRewardHandler inRewardHandler2)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rewardHandler2 = inRewardHandler2;
    }

    /**
     * @notice Increases a users staked amount of dao tokens.
     * @param inTokenAdd The address of the token type to stake.
     * @param inAmount The amount to stake.
     */
    function stakeDaoToken(
        address inTokenAdd,
        uint256 inAmount
    )
        external
        whenNotPaused
        onlyAllowedToken(inTokenAdd)
    {
        address owner = msg.sender;
        if (inAmount == 0) {
            emit StakedZero(owner, inTokenAdd);
            return;
        }

        (
            TokenAvailability res,
            uint256 available
        ) = owner.checkAllowanceAndBalance(
            inAmount,
            inTokenAdd,
            address(tokenTransferProxy)
        );
        if (res == TokenAvailability.InsufficientBalance) {
            revert InsufficientBalance({
                available: available,
                required: inAmount
            });
        } else if (res == TokenAvailability.InsufficientAllowance) {
            revert InsufficientAllowance({
                available: available,
                required: inAmount
            });
        }
        _stake(owner, inAmount);
    }

    /**
     * @notice Decreases a users staked amount of dao tokens.
     * @param inStakedTokenAdd The staked token type to return from the user.
     * @param inAmount The amount to unstake.
     */
    function unstakeDaoToken(
        address inStakedTokenAdd,
        uint256 inAmount
    )
        external
        whenNotPaused
        onlyAllowedDistToken(inStakedTokenAdd)
    {
        address owner = msg.sender;
        unstakeTokens(owner, inAmount);
    }

    /**
     * @notice Let the owner of staked tokens unstake them all again.
     * @param inStakedTokenAdd The staked token type to return from the user.
     */
    function unstakeAllTokens(address inStakedTokenAdd)
        external
        override
        whenNotPaused
        onlyAllowedDistToken(inStakedTokenAdd)
    {
        address owner = msg.sender;
        uint256 sdtBalance = IERC20(inStakedTokenAdd).balanceOf(owner);
        unstakeTokens(owner, sdtBalance);
    }

    /**
     * @notice Let the admin of this contract unstake all tokens of a user.
     * @param owner The user to update.
     * @param inStakedTokenAdd The staked token type to return from the user.
     */
    function returnAllStakedTokensAsAdmin(
        address owner,
        address inStakedTokenAdd
    )
        external
        override
        whenNotPaused
        onlyAllowedDistToken(inStakedTokenAdd)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 sdtBalance = IERC20(inStakedTokenAdd).balanceOf(owner);
        unstakeTokens(owner, sdtBalance);
    }

    /**
     * @notice Unstake by unswapping tokens and burn the dist token.
     * @param owner The user to update.
     * @param inAmount The amount of staked tokens to return.
     */
    function unstakeTokens(
        address owner,
        uint256 inAmount
    )
        internal
    {
        if (inAmount == 0) {
            emit UnstakedZero(owner, address(stakedToken));
            return;
        }

        (
            TokenAvailability res,
            uint256 available
        ) = owner.checkAllowanceAndBalance(
            inAmount,
            address(stakedToken),
            address(this)
        );
        if (res == TokenAvailability.InsufficientBalance) {
            revert InsufficientBalance({
                available: available,
                required: inAmount
            });
        } else if (res == TokenAvailability.InsufficientAllowance) {
            revert InsufficientAllowance({
                available: available,
                required: inAmount
            });
        }
        _unstake(owner, inAmount);
    }

    /**
     * @notice Increases a users staked amount of dao tokens.
     * @param owner The owner to update.
     * @param inAmount The amount to stake.
     */
    function _stake(
        address owner,
        uint256 inAmount
    ) internal {
        transferViaProxy(owner, daoToken, address(this), inAmount);
        _lock(owner, daoToken, inAmount);

        // Update stakers assigned rewards, using old distribution
        rewardHandler1.updateRewards(owner, stakedToken);
        rewardHandler2.updateRewards(owner, stakedToken);

        // Now mint stakers new tokens.

        ILPToken(stakedToken).mint(owner, inAmount);

        emit TokensStaked(owner, daoToken, inAmount);
    }

    /**
     * @notice Return staked tokens to user and burn their DistTokens.
     * @param owner The user to update.
     * @param inAmount The amount of DistTokens to return.
     */
    function _unstake(
        address owner,
        uint256 inAmount
    ) private {
        // Update stakers assigned rewards, before before burning tokens.
        rewardHandler1.updateRewards(owner, stakedToken);
        rewardHandler2.updateRewards(owner, stakedToken);

        ILPToken(stakedToken).burnFrom(owner, inAmount);
        _unlock(owner, daoToken, inAmount);

        // Return the staked tokens
        IERC20(daoToken).transfer(owner, inAmount);

        emit TokensUnstaked(owner, stakedToken, inAmount);
    }

    /*
      * @notice Transfers a token using TokenTransferProxy.transferFrom().
      * @param from Address transfering token.
      * @param inTokenAdd Address of token to transferFrom.
      * @param to Address receiving token.
      * @param value Amount of token to transfer.
      * @return Success of token transfer.
      */
    function transferViaProxy(
        address from,
        address inTokenAdd,
        address to,
        uint256 value
    )
        private
        returns (bool)
    {
        return tokenTransferProxy.transferFrom(inTokenAdd, from, to, value);
    }
}


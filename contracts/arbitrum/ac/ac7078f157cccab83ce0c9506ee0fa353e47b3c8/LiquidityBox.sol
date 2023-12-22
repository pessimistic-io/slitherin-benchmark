// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ILiquidityBox.sol";
import "./TokenValidator.sol";
import "./IERC20.sol";
// For debugging only


/**
 * @title Liquidity Box
 * @author Deepp Dev Team
 * @notice Abstract contract for storing tokens in a locked state.
 * @notice This is a sub contract for the BookieMain app.
 * @notice Its keeps a list of locked tokens and owns the locked tokens.
 * @notice TokenValidator is Accesshandler, Accesshandler is Initializable.
 */
abstract contract LiquidityBox is ILiquidityBox, TokenValidator {

    ITokenTransferProxy private tokenTransferProxy;
    ILockBox internal extLockBox;
    IRewardHandler private feeHandler1;
    IRewardHandler private feeHandler2;
    IRewardHandler private rewardHandler1;
    IRewardHandler private rewardHandler2;

    uint8 private feePermille;
    uint8 private feeSplitPercent1;
    uint8 private feeSplitPercent2;

    /**
     * Event that fires when tokens are deposited.
     * @param owner is the address that deposited tokens.
     * @param tokenAdd is the token contract address.
     * @param amount is the amount deposited, after fee deduction.
     * @param fee is the fee paid.
     */
    event TokensDeposited(
        address indexed owner,
        address tokenAdd,
        uint256 amount,
        uint256 fee
    );

    /**
     * Event that fires when tokens are withdrawn.
     * @param owner is the address that withdrew tokens.
     * @param tokenAdd is the token contract address.
     * @param amount is the amount withdrawn, including the fee.
     * @param fee is the fee paid.
     */
    event TokensWithdrawn(
        address indexed owner,
        address tokenAdd,
        uint256 amount,
        uint256 fee
    );

    /**
     * @notice Event fires when deposit for 0 tokens is attempted.
     * @param owner is the owner of the tokens.
     * @param tokenAdd is the token contract address.
     */
    event DepositZero(address indexed owner, address tokenAdd);

    /**
     * @notice Event fires when withdraw for 0 distTokens is attempted.
     * @param owner is the owner of the distTokens.
     * @param distToken is the distToken contract address.
     */
    event WithdrawZero(address indexed owner, address distToken);

    /**
     * @notice Event fires when fees are set.
     * @param feePermille is the fee permille to charge.
     * @param feePercent1 is the percent of the fee that goes to handler 1.
     * @param feePercent2 is the percent of the fee that goes to handler 2.
     */
    event FeesSet(
        uint8 feePermille,
        uint8 feePercent1,
        uint8 feePercent2
    );

    /**
     * @notice Event fires when invalid fees are set.
     * @param feePermille is the fee permille to charge.
     * @param feePercent1 is the percent of the fee that goes to handler 1.
     * @param feePercent2 is the percent of the fee that goes to handler 2.
     */
    error InvalidFees(
        uint8 feePermille,
        uint8 feePercent1,
        uint8 feePercent2
    );

    /**
     * Error for Insufficient liquidity balance for withdrawel.
     * Needed `required` but only `available` available.
     * @param available balance available.
     * @param required requested amount to transfer.
     */
    error InsufficientBalance(uint256 available, uint256 required);

    /**
     * Error for Insufficient DistToken balance for withdrawal.
     * Needed `required` but only `available` available.
     * @param available balance available.
     * @param required requested amount to transfer.
     */
    error InsufficientDistTokenBalance(uint256 available, uint256 required);

    /**
     * Error for Insufficient DistToken allowance for withdrawal.
     * Needed `required` but only `available` available.
     * @param available allowance available.
     * @param required requested amount to transfer.
     */
    error InsufficientAllowance(uint256 available, uint256 required);

    /**
     * Error for token transfer failure, when trying to deposit.
     * @param user is the address that tried to deposit.
     * @param tokenAdd is the token contract address
     * @param amount is the requested amount to transfer, including the fee.
     */
    error TokenDepositFailed(address user, address tokenAdd, uint256 amount);

    /**
     * Error for token transfer failure during a withdraw request.
     * @param receiver is the address to receive the tokens.
     * @param tokenAdd is the token contract address.
     * @param amount is the requested amount to transfer, including the fee.
     */
    error TokenWithdrawFailed(
        address receiver,
        address tokenAdd,
        uint256 amount
    );

    /**
     * Error for account address 0.
     */
    error BadAccountZero();

    /**
     * @notice Default constructor.
     */
    constructor() TokenValidator() {}

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inDistToken The Token used to account for deposited funds.
     * @param inTokenTransferProxy The TokenTransferProxy contract  address.
     * @param inExtLockBox Is a contract that holds externally locked tokens.
     * @param inFeeHandler1 Is 1st contract that handles dep/wtd fees.
     * @param inFeeHandler2 Is 2nd contract that handles dep/wtd fees.
     * @param inRewardHandler1 Is 1st contract that handles LPT rewards.
     * @param inRewardHandler2 Is 2nd contract that handles LPT rewards.
     * @param inFeePermille Is the fee permille to charge.
     * @param inFeePercent1 Is percent of fees that goes to handler 1.
     * @param inFeePercent2 Is percent of fees that goes to handler 2.
     */
    function initBox(
        IDistToken inDistToken,
        ITokenTransferProxy inTokenTransferProxy,
        ILockBox inExtLockBox,
        IRewardHandler inFeeHandler1,
        IRewardHandler inFeeHandler2,
        IRewardHandler inRewardHandler1,
        IRewardHandler inRewardHandler2,
        uint8 inFeePermille,
        uint8 inFeePercent1,
        uint8 inFeePercent2
    )
        external
        notInitialized
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _initFees(
            inFeeHandler1,
            inFeeHandler2,
            inRewardHandler1,
            inRewardHandler2,
            inFeePermille,
            inFeePercent1,
            inFeePercent2);

        _initBox(
            inDistToken,
            inTokenTransferProxy,
            inExtLockBox);
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
     * @notice Setter to change the referenced feeHandler1 contract.
     * @param inFeeHandler1 Is 1st contract that handles dep/wtd fees.
     */
    function setFeeHandler1(IRewardHandler inFeeHandler1)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        feeHandler1 = inFeeHandler1;
    }

    /**
     * @notice Setter to change the referenced feeHandler2 contract.
     * @param inFeeHandler2 Is 2nd contract that handles dep/wtd fees.
     */
    function setFeeHandler2(IRewardHandler inFeeHandler2)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        feeHandler2 = inFeeHandler2;
    }

    /**
     * @notice Setter to change the referenced rewardHandler1 contract.
     * @param inRewardHandler1 Is 1st contract that handles LPT rewards.
     */
    function setRewardHandler1(IRewardHandler inRewardHandler1)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rewardHandler1 = inRewardHandler1;
    }

    /**
     * @notice Setter to change the referenced rewardHandler2 contract.
     * @param inRewardHandler2 Is 2nd contract that handles LPT rewards.
     */
    function setRewardHandler2(IRewardHandler inRewardHandler2)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        rewardHandler2 = inRewardHandler2;
    }


    /**
     * @notice Sets the amount of fees to charge and distribute.
     * @param inFeePermille is the fee permille to charge.
     * @param inFeePercent1 is the percent of the fee that goes to handler 1.
     * @param inFeePercent2 is the percent of the fee that goes to handler 2.
     */
    function setFees(
        uint8 inFeePermille,
        uint8 inFeePercent1,
        uint8 inFeePercent2
    )
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setFees(inFeePermille, inFeePercent1, inFeePercent2);
    }

    /**
     * @notice Gets balance of a DistToken, from the referenced token.
     * @param owner Is the address that owns the DistTokens.
     * @param tokenAdd The token type that matches the DistToken.
     * @return uint256 The amount owned by the address.
     */
    function getDistTokenBalanceFromToken(address owner, address tokenAdd)
        external
        override
        view
        onlyAllowedToken(tokenAdd)
        returns (uint256)
    {
        return IERC20(allowedTokens[tokenAdd]).balanceOf(address(owner));
    }

    /**
     * @notice Gets the boxs available balance for a token.
     * @param tokenAdd The address of the token type.
     * @return uint256 The amount currently owned.
     */
    function getTokenBalance(address tokenAdd) public view returns (uint256) {
        return IERC20(tokenAdd).balanceOf(address(this));
    }

    /**
     * @notice Gets the boxs full balance for a token, including the amount
     *         currently locked in external box.
     * @param tokenAdd The token type.
     * @return uint256 The combined box balance.
     */
    function getFullBalance(address tokenAdd) public view returns (uint256) {
        uint256 fullTokenBalance = IERC20(tokenAdd).balanceOf(address(this));
        if (address(extLockBox) != address(0)) {
            fullTokenBalance += extLockBox.getLockedAmount(address(this), tokenAdd);
        }
        return fullTokenBalance;
    }

    /**
     * @notice Gets the matching token valueof an amount of DistTokens.
     * @param distTokenAdd The address of DistToken type.
     * @param amount The amount of DistTokens.
     * @return tokenAmount The matching amount.
     */
    function getMatchingTokenAmount(address distTokenAdd, uint256 amount)
        public
        override
        view
        returns (uint256 tokenAmount)
    {
        address tokenAdd = IDistToken(distTokenAdd).tokenAdd();
        uint256 totalSupplyDist = IERC20(distTokenAdd).totalSupply();
        if (amount == 0 || totalSupplyDist == 0) {
            return 0;
        }
        tokenAmount = getFullBalance(tokenAdd) * amount / totalSupplyDist;
    }

    /**
     * @notice Gets the matching DistToken value of an amount of ERC20 Tokens.
     * @param tokenAdd The ERC20 token type.
     * @param amount The amount of tokens.
     * @return distTokenAmount The matching amount.
     */
    function getMatchingDistTokenAmount(address tokenAdd, uint256 amount)
        public
        override
        view
        onlyAllowedToken(tokenAdd)
        returns (uint256 distTokenAmount)
    {
        address distToken = allowedTokens[tokenAdd];
        uint256 totalSupplyDist = IERC20(distToken).totalSupply();
        if (amount == 0 || totalSupplyDist == 0) {
            return 0;
        }
        distTokenAmount = totalSupplyDist * amount / getFullBalance(tokenAdd);
    }

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inDistToken The Token used to keep the liquidity balance.
     * @param inTokenTransferProxy The TokenTransferProxy contract  address.
     * @param inExtLockBox Is a contract that holds externally locked tokens.
     */
    function _initBox(
        IDistToken inDistToken,
        ITokenTransferProxy inTokenTransferProxy,
        ILockBox inExtLockBox
    )
        internal
        notInitialized
    {
        extLockBox = inExtLockBox;
        tokenTransferProxy = inTokenTransferProxy;

        // Add the tokens to the list of accepted tokens.
        _addTokenPair(inDistToken.tokenAdd(), address(inDistToken));

        BaseInitializer.initialize();
    }

    /**
     * @notice Initializes this contract with fees details.
     * @param inFeeHandler1 Is 1st contract that handles dep/wtd fees.
     * @param inFeeHandler2 Is 2nd contract that handles dep/wtd fees.
     * @param inRewardHandler1 Is 1st contract that handles LPT rewards.
     * @param inRewardHandler2 Is 2nd contract that handles LPT rewards.
     * @param inFeePermille is the fee permille to charge.
     * @param inFeePercent1 Is percent of fees that goes to handler 1.
     * @param inFeePercent2 Is percent of fees that goes to handler 2.
     */
    function _initFees(
        IRewardHandler inFeeHandler1,
        IRewardHandler inFeeHandler2,
        IRewardHandler inRewardHandler1,
        IRewardHandler inRewardHandler2,
        uint8 inFeePermille,
        uint8 inFeePercent1,
        uint8 inFeePercent2
    )
        internal
        notInitialized
    {
        feeHandler1 = inFeeHandler1;
        feeHandler2 = inFeeHandler2;
        rewardHandler1 = inRewardHandler1;
        rewardHandler2 = inRewardHandler2;
        _setFees(inFeePermille, inFeePercent1, inFeePercent2);
    }

    /**
     * @notice Increases the users deposited amount for a token.
     * @param owner The owner to update.
     * @param tokenAdd The address of the token type to deposit.
     * @param amount The amount to deposit, including the fee.
     */
    function _deposit(
        address owner,
        address tokenAdd,
        uint256 amount
    ) internal {
        IDistToken distToken = IDistToken(allowedTokens[tokenAdd]);
        uint256 totalSupply = distToken.totalSupply();
        uint256 fee;
        if (feePermille > 0)
            fee = amount * feePermille / 1000;

        // The amount added, when fee is deducted.
        uint256 addAmount = amount - fee;
        // Minting same amount of dist, if it's first deposit.
        uint256 distAmount = addAmount;
        if (totalSupply > 0) {
            // This is not the first deposit
            // Calc the rel increase of token balance, and mint the same rel
            // amount of DistTokens
            uint256 fullTokenBalance = getFullBalance(tokenAdd);
            distAmount = addAmount * totalSupply / fullTokenBalance;
        }

        bool success = transferViaProxy(owner, tokenAdd, address(this), amount);
        if (!success) {
            revert TokenDepositFailed({
                user: owner,
                tokenAdd: tokenAdd,
                amount: amount
            });
        }

        if (fee > 0) {
            // Update the pools rewards, before minting DistTokens
            if (feeSplitPercent1 > 0) {
                // Add the fee to the common reward pools
                uint256 fee1 = fee * feeSplitPercent1 / 100;
                feeHandler1.addRewards(owner, tokenAdd, fee1);
                // Transfer the fee to the reward handler
                IERC20(tokenAdd).transfer(address(feeHandler1), fee1);
            }
            if (feeSplitPercent2 > 0) {
                // Add the fee to the common reward pools
                uint256 fee2 = fee * feeSplitPercent2 / 100;
                feeHandler2.addRewards(owner, tokenAdd, fee2);
                // Transfer the fee to the reward handler
                IERC20(tokenAdd).transfer(address(feeHandler2), fee2);
            }
        }
        // Update depositors assigned rewards, using old distribution
        rewardHandler1.updateRewards(owner, address(distToken));
        rewardHandler2.updateRewards(owner, address(distToken));

        // Now mint depositors new tokens.

        distToken.mint(owner, distAmount);
        emit TokensDeposited(owner, tokenAdd, addAmount, fee);
    }

    /**
     * @notice Return deposited tokens to user and burn their DistTokens.
     * @param owner The user to update.
     * @param distTokenAdd The address of DistToken type to return.
     * @param amount The amount of DistTokens to return.
     * @return bool True if the withdraw succeeded, false if not.
     */
    function _withdraw(
        address owner,
        address distTokenAdd,
        uint256 amount
    ) internal returns (bool) {
        if (amount == 0) {
            emit WithdrawZero(owner, distTokenAdd);
            return false;
        }
        IDistToken distToken = IDistToken(distTokenAdd);
        uint256 distTokenBalance = distToken.balanceOf(owner);
        if (amount > distTokenBalance) {
            revert InsufficientDistTokenBalance({
                available: distTokenBalance,
                required: amount
            });
        }
        uint256 allowance = distToken.allowance(owner, address(this));
        if (amount > allowance) {
            revert InsufficientAllowance({
                available: allowance,
                required: amount
            });
        }
        address tokenAdd = distToken.tokenAdd();
        uint256 tokenAmount = getMatchingTokenAmount(distTokenAdd, amount);
        uint256 availableBalance = getTokenBalance(tokenAdd);
        if (tokenAmount > availableBalance) {
            revert InsufficientBalance({
                available: availableBalance,
                required: tokenAmount
            });
        }
        uint256 returnAmount = tokenAmount;
        uint256 fee;
        if (feePermille > 0) {
            fee = tokenAmount * feePermille / 1000;
            returnAmount -= fee;

            // Update withdrawers assigned rewards, before before burning tokens
            rewardHandler1.updateRewards(owner, address(distToken));
            rewardHandler2.updateRewards(owner, address(distToken));
            // Burn the holders tokens before adding new rewards
            distToken.burnFrom(owner, amount);
            if (feeSplitPercent1 > 0) {
                uint256 fee1 = fee * feeSplitPercent1 / 100;
                // Add the fee to the common reward pool
                feeHandler1.addRewards(owner, tokenAdd, fee1);
                // Transfer the fee to the reward handler
                IERC20(tokenAdd).transfer(address(feeHandler1), fee1);
            }
            if (feeSplitPercent2 > 0) {
                uint256 fee2 = fee * feeSplitPercent2 / 100;
                // Add the fee to the common reward pool
                feeHandler2.addRewards(owner, tokenAdd, fee2);
                // Transfer the fee to the reward handler
                IERC20(tokenAdd).transfer(address(feeHandler2), fee2);
            }
        }
        // Return the withdrawn tokens, after fee deduction
        bool success = IERC20(tokenAdd).transfer(owner, returnAmount);
        if (!success) {
            revert TokenWithdrawFailed({
                receiver: owner,
                tokenAdd: tokenAdd,
                amount: tokenAmount
            });
        }

        emit TokensWithdrawn(owner, tokenAdd, tokenAmount, fee);
        return true;
    }

    /**
     * @notice Transfer own tokens to external box, and locks.
     * @param tokenAdd The token type to transfer.
     * @param amount The amount to transfer.
     */
    function _moveToExt(address tokenAdd, uint256 amount) internal {
        if (amount == 0)
            return;
        if (address(extLockBox) == address(0))
            revert BadAccountZero();

        uint256 bal = getTokenBalance(tokenAdd);
        if (amount > bal) {
            revert InsufficientBalance({
                available: bal,
                required: amount
            });
        }
        IERC20(tokenAdd).transfer(address(extLockBox), amount);
        extLockBox.lockAmount(address(this), tokenAdd, amount);
    }

    /**
     * @notice Sets the amount of fees to charge and distribute.
     * @param inFeePermille is the fee permille to charge.
     * @param inFeePercent1 is the percent of the fee that goes to handler 1.
     * @param inFeePercent2 is the percent of the fee that goes to handler 2.
     */
    function _setFees(
        uint8 inFeePermille,
        uint8 inFeePercent1,
        uint8 inFeePercent2
    ) private {
        if (inFeePermille > 0 &&
            (inFeePercent1 > 100 || inFeePercent2 > 100 ||
            inFeePercent1 + inFeePercent2 != 100))
        {
            revert InvalidFees({
                feePermille: inFeePermille,
                feePercent1: inFeePercent1,
                feePercent2: inFeePercent2
            });
        }
        feePermille = inFeePermille;
        feeSplitPercent1 = inFeePercent1;
        feeSplitPercent2 = inFeePercent2;
        emit FeesSet(feePermille, feeSplitPercent1, feeSplitPercent2);
    }

    /**
     * @notice Transfers tokens using TokenTransferProxy.
     * @param owner Address transfering tokens from.
     * @param tokenAdd Address of token type to transfer.
     * @param to Address receiving tokens.
     * @param value Amount of tokens to transfer.
     * @return bool Success of tokens transfer.
     */
    function transferViaProxy(
        address owner,
        address tokenAdd,
        address to,
        uint256 value
    ) private returns (bool) {
        return tokenTransferProxy.transferFrom(tokenAdd, owner, to, value);
    }
}


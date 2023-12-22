// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


import "./IBetHistory.sol";
import "./AccessHandler.sol";
import "./BetData.sol";
import "./IERC20.sol";
// For debugging only


/**
 * @title Bet History
 * @author Deepp Dev Team
 * @notice Simple contract for historical bet data.
 * @notice This is a sub contract for the Bookie app.
 * @notice Accesshandler is Initializable.
 */
contract BetHistory is IBetHistory, AccessHandler {
    IBetHelper private lp;
    ILockBox private betLockBox;
    IMarketHistory private marketHistory;
    ITokenTransferProxy private tokenTransferProxy;
    IRewardHandler private feeHandler1;
    IRewardHandler private feeHandler2;

    uint8 private feePermille;
    uint8 private feeSplitPercent1;
    uint8 private feeSplitPercent2;

    // bet hash => Bet (struct)
    mapping(bytes32 => BetData.Bet) public allBets;
    // bet hash => pot size
    mapping(bytes32 => uint256) public unsettledPots;
    // market hash => tokenAdd => amount betted
    mapping(bytes32 => mapping(address => uint256)) public marketBetted;
    // market hash => tokenAdd => amount matched
    mapping(bytes32 => mapping(address => uint256)) public marketMatched;

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
     * Error for token transfer failure, prob due to lack of tokens.
     * @param receiver is the address of the payout receiver.
     * @param tokenAdd is the token contract address
     * @param amount is the desired amount to pay.
     */
    error PayoutFailed(address receiver, address tokenAdd, uint256 amount);

    /**
     * @notice Error for token transfer when betting,
     *         although balance should be available.
     * @param better is the address to transfer the tokens.
     * @param token is the token contract address
     * @param amount is the requested amount to transfer.
     */
    error TokenPaymentFailed(address better, address token, uint256 amount);

    /**
     * @notice Error fires when bet does not exist.
     * @param betHash is the bets hash used for lookup.
     */
    error BetNotFound(bytes32 betHash);

    /**
     * @notice Checks if a bet exists (otherwise 0).
     * @param betHash The hash of the bet to check.
     */
    modifier betExists(bytes32 betHash) {
        BetData.Bet storage bet = allBets[betHash];
        if (bet.amount == 0)
            revert BetNotFound({betHash: betHash});
        _;
    }

    /**
     * @notice Default Constructor.
     */
    constructor() {}

    /*
     * @notice Initializes this contract with reference to other contracts.
     * @param inLP The Liquidity Pool contract, to match bets.
     * @param inBetLockBox The bet LockBox contract address.
     * @param inMarketHistory The market history contract for storing markets.
     * @param inTokenTransferProxy The TokenTransferProxy contract address.
     * @param inFeeHandler1 The 1st fee handler contract address.
     * @param inFeeHandler2 The 2nd fee handler contract address.
     * @param inFeePermille is the fee permille to charge.
     * @param inFeePercent1 is the percent of the fee that goes to handler 1.
     * @param inFeePercent2 is the percent of the fee that goes to handler 2.
     */
    function init(
        IBetHelper inLP,
        ILockBox inBetLockBox,
        IMarketHistory inMarketHistory,
        ITokenTransferProxy inTokenTransferProxy,
        IRewardHandler inFeeHandler1,
        IRewardHandler inFeeHandler2,
        uint8 inFeePermille,
        uint8 inFeePercent1,
        uint8 inFeePercent2
    )
        external
        notInitialized
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        lp = inLP;
        betLockBox = inBetLockBox;
        marketHistory = inMarketHistory;
        tokenTransferProxy = inTokenTransferProxy;

        _initFees(
            inFeeHandler1,
            inFeeHandler2,
            inFeePermille,
            inFeePercent1,
            inFeePercent2);

        BaseInitializer.initialize();
    }

    /**
     * @notice Setter to change the referenced LiquidityPool contract.
     * @param inLP The Liquidity Pool contract, to match bets.
     */
    function setLiquidityPool(IBetHelper inLP)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        lp = inLP;
    }

    /**
     * @notice Setter to change the referenced bet LockBox contract.
     * @param inBetLockBox The bet LockBox contract address.
     */
    function setBetLockBox(ILockBox inBetLockBox)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        betLockBox = inBetLockBox;
    }

    /**
     * @notice Setter to change the referenced MarketHistory contract.
     * @param inMarketHistory The market history contract for storing markets.
     */
    function setMarketHistory(IMarketHistory inMarketHistory)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        marketHistory = inMarketHistory;
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
     * @param inFeeHandler1 Is 1st contract that handles bet win fees.
     */
    function setFeeHandler1(IRewardHandler inFeeHandler1)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        feeHandler1 = inFeeHandler1;
    }

    /**
     * @notice Setter to change the referenced feeHandler2 contract.
     * @param inFeeHandler2 Is 2nd contract that handles bet win fees.
     */
    function setFeeHandler2(IRewardHandler inFeeHandler2)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        feeHandler2 = inFeeHandler2;
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
     * @notice Create bet, by storing the bet details.
     * @param bet is the details data.
     */
    function createBet(BetData.Bet calldata bet)
        external
        override
        isInitialized
        onlyRole(BETTER_ROLE)
    {
        bytes32 betHash = BetData.getBetHash(bet);
        uint256 betAmount = bet.amount;

        // Lock and transfer the betters tokens first
        bool success = transferViaProxy(
            bet.owner,
            bet.token,
            address(betLockBox),
            bet.amount
        );
        if (!success) {
            revert TokenPaymentFailed({
                better: bet.owner,
                token: bet.token,
                amount: bet.amount
            });
        }
        betLockBox.lockAmount(bet.owner, bet.token, betAmount);

        // Lock and transfer LPs tokens to the lockbox too.
        uint256 pot = betAmount * bet.decimalOdds / BetData.ODDS_PRECISION;
        uint256 matchedAmount = pot - betAmount;
        matchBet(bet.marketHash, bet.token, matchedAmount);

        // bet hash => Bet (struct)
        allBets[betHash] = bet;
        // bet hash => pot
        unsettledPots[betHash] = pot;
        // market hash => tokenAdd => amount betted
        marketBetted[bet.marketHash][bet.token] += betAmount;

        // Just debugging

    }

    /**
     * @notice Settle bet, by resetting the unsettled amount,
               unlocking tokens and paying the pot to LP or better.
     * @param betHash is the key used to look up the bet data.
     * @return result contains all the details of the settlement.
     */
    function settleBet(bytes32 betHash)
        external
        override
        betExists(betHash)
        onlyRole(BETTER_ROLE)
        returns (BetData.BetSettleResult memory result)
    {
        BetData.Bet storage bet = allBets[betHash];
        BetData.logBet(bet);

        // Check that market is settled/completed
        marketHistory.assertMarketIsCompleted(bet.marketHash);

        // Get the pot and reset
        uint256 potSize = unsettledPots[betHash];
        unsettledPots[betHash] = 0;
        result.better = bet.owner;
        result.tokenAdd = bet.token;
        result.paidToBetter = 0;
        result.paidToLP = 0;
        result.paidToFee = 0;

        uint256 betAmount = bet.amount;
        uint256 lockedAmount = betLockBox.getLockedAmount(result.better, result.tokenAdd);
        if (lockedAmount == 0 || potSize == 0) {
            return result;
        }


        // Unlock the betters and the LPs tokens
        betLockBox.unlockAmountTo(
            result.better,
            address(tokenTransferProxy),
            result.tokenAdd,
            betAmount);

        uint256 matchedAmount = potSize - betAmount;

        betLockBox.unlockAmountTo(
            address(lp),
            address(tokenTransferProxy),
            result.tokenAdd,
            matchedAmount);

        bool canceled = marketHistory.isMarketOutcome(
            bet.marketHash,
            IMarketHistory.MarketOutcome.Cancel
        );
        bool isVoid = marketHistory.isMarketOutcome(
            bet.marketHash,
            IMarketHistory.MarketOutcome.Void
        );
        // Market was cancelled or void, just return both parties investment
        if (canceled || isVoid) {
            result.paidToBetter = betAmount;
            result.paidToLP = matchedAmount;
            // Pay the better
            _payBetter(result.better, result.tokenAdd, result.paidToBetter);
            // Return to LP
            _payLP(result.tokenAdd, result.paidToLP);
            return result;
        }
        // Win
        if (marketHistory.isMarketOutcome(
                bet.marketHash,
                IMarketHistory.MarketOutcome.Win
            )
        ) {
            //Better won give them the full pot - win fee
            result.paidToFee = matchedAmount * feePermille / 1000;
            result.paidToBetter = potSize - result.paidToFee;
            // Add the fee to the common reward pools
            _payFees(result.better, result.tokenAdd, result.paidToFee);
            // Pay the better
            _payBetter(result.better, result.tokenAdd, result.paidToBetter);
            return result;
        }
        // HalfWin
        if (marketHistory.isMarketOutcome(
                bet.marketHash,
                IMarketHistory.MarketOutcome.HalfWin
            )
        ) {
            // Half the matched amount is returned to the LP.
            // Better won half: Give them half the pot - win fee,
            // and return half the bet amount as well.
            result.paidToLP = matchedAmount / 2;
            result.paidToFee = result.paidToLP * feePermille * 1000;
            result.paidToBetter = potSize - result.paidToFee - result.paidToLP;
            // Add the fee to the common reward pools
            _payFees(result.better, result.tokenAdd, result.paidToFee);
            // Pay the better
            _payBetter(result.better, result.tokenAdd, result.paidToBetter);
            // Return to LP
            _payLP(result.tokenAdd, result.paidToLP);
            return result;
        }
        // HalfLoss
        if (marketHistory.isMarketOutcome(
                bet.marketHash,
                IMarketHistory.MarketOutcome.HalfLoss
            )
        ) {
            // Return half the bet amount to the better.
            // Return the rest to the LP.
            result.paidToBetter = betAmount / 2;
            result.paidToLP = potSize - result.paidToBetter;
            // Pay the better
            _payBetter(result.better, result.tokenAdd, result.paidToBetter);
            // Return to LP
            _payLP(result.tokenAdd, result.paidToLP);
            return result;
        }
        // Loss
        if (marketHistory.isMarketOutcome(
                bet.marketHash,
                IMarketHistory.MarketOutcome.Loss
            )
        ) {
            //Better lost send the full pot to the LP
            result.paidToLP = potSize;
            // Return to LP
            _payLP(result.tokenAdd, result.paidToLP);
            return result;
        }
        // Invalid outcome, the outcome must be undefined
        revert("INVALID_OUTCOME");
    }

    /**
     * @notice Cancel bet, by resetting the unsettled amount,
               unlocking and paying back tokens to LP and better.
     * @param betHash is the key used to look up the bet data.
     * @return result contains all the details of the canceling.
     */
    function cancelBet(bytes32 betHash)
        external
        override
        betExists(betHash)
        onlyRole(BETTER_ROLE)
        returns (BetData.BetSettleResult memory result)
    {
        BetData.Bet storage bet = allBets[betHash];

        // Check that market is still open (active)
        marketHistory.assertMarketIsActive(bet.marketHash); // TODO: Should cancel be available in other states like Playing?

        // Get the pot and reset
        uint256 betAmount = bet.amount;
        result.better = bet.owner;
        result.tokenAdd = bet.token;
        uint256 potSize = unsettledPots[betHash];
        uint256 lockedAmount = betLockBox.getLockedAmount(bet.owner, bet.token);
        if (lockedAmount == 0 || potSize == 0) {
            return result;
        }

        uint256 matchedAmount = potSize - betAmount;
        marketBetted[bet.marketHash][bet.token] -= betAmount;
        marketMatched[bet.marketHash][bet.token] -= matchedAmount;
        unsettledPots[betHash] = 0;

        // Unlock the betters and the LPs tokens
        betLockBox.unlockAmountTo(
            bet.owner,
            address(tokenTransferProxy),
            bet.token,
            betAmount);
        betLockBox.unlockAmountTo(
            address(lp),
            address(tokenTransferProxy),
            bet.token,
            matchedAmount);

        result.paidToBetter = betAmount;
        result.paidToLP = matchedAmount;
        // Pay the better
        _payBetter(bet.owner, bet.token, result.paidToBetter);
        // Return to LP
        _payLP(bet.token, result.paidToLP);
    }

    /**
     * @notice Check if a bet exists, based on its hash.
     * @param betHash is the key used to look up the bet data.
     * @return True if the bet was found, false if not.
     */
    function getBetExists(bytes32 betHash) external view returns(bool) {
        if (allBets[betHash].amount == 0)
            return false;
        return true;
    }

    /**
     * @notice Initializes this contract with fees details.
     * @param inFeeHandler1 is 1st contract that handles dep/wtd fees.
     * @param inFeeHandler2 is 2nd contract that handles dep/wtd fees.
     * @param inFeePermille is the fee permille to charge.
     * @param inFeePercent1 Is percent of fees that goes to handler 1.
     * @param inFeePercent2 Is percent of fees that goes to handler 2.
     */
    function _initFees(
        IRewardHandler inFeeHandler1,
        IRewardHandler inFeeHandler2,
        uint8 inFeePermille,
        uint8 inFeePercent1,
        uint8 inFeePercent2
    )
        internal
        notInitialized
    {
        feeHandler1 = inFeeHandler1;
        feeHandler2 = inFeeHandler2;
        _setFees(inFeePermille, inFeePercent1, inFeePercent2);
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
     * @notice Pays fees to the allocated handlers.
     * @param inBetter is the better that pays the fees.
     * @param tokenAdd is the address of the token type.
     * @param inAmount is the fee amount.
     */
    function _payFees(address inBetter, address tokenAdd, uint256 inAmount)
        private
    {
        if (feePermille > 0) {
            // Update the pools rewards
            if (feeSplitPercent1 > 0) {
                // Add the fee to the common reward pool
                uint256 fee1 = inAmount * feeSplitPercent1 / 100;
                feeHandler1.addRewards(inBetter, tokenAdd, fee1);
                // Transfer the fee to the reward handler
                bool success = transferViaProxy(
                    address(betLockBox),
                    tokenAdd,
                    address(feeHandler1),
                    fee1
                );
                if (!success) {
                    revert PayoutFailed({
                        receiver: address(feeHandler1),
                        tokenAdd: tokenAdd,
                        amount: fee1
                    });
                }
            }
            if (feeSplitPercent2 > 0) {
                // Add the fee to the common reward pool
                uint256 fee2 = inAmount * feeSplitPercent2 / 100;
                feeHandler2.addRewards(inBetter, tokenAdd, fee2);
                // Transfer the fee to the reward handler
                bool success = transferViaProxy(
                    address(betLockBox),
                    tokenAdd,
                    address(feeHandler2),
                    fee2
                );
                if (!success) {
                    revert PayoutFailed({
                        receiver: address(feeHandler2),
                        tokenAdd: tokenAdd,
                        amount: fee2
                    });
                }
            }
        }
    }

    /**
     * @notice Pays a won/void bet to the better.
     * @param inBetter is the better address.
     * @param tokenAdd is the address of the token type.
     * @param inAmount is the win amount.
     */
    function _payBetter(address inBetter, address tokenAdd, uint256 inAmount)
        private
    {
        // Pay to better
        if (inAmount > 0) {
            bool success = transferViaProxy(
                address(betLockBox),
                tokenAdd,
                inBetter,
                inAmount
            );
            if (!success) {
                revert PayoutFailed({
                    receiver: inBetter,
                    tokenAdd: tokenAdd,
                    amount: inAmount
                });
            }
        }
    }

    /**
     * @notice Pays a lost/void bet back to the LP.
     * @param tokenAdd is the address of the token type.
     * @param inAmount is the amount returned.
     */
    function _payLP(address tokenAdd, uint256 inAmount) private {
        // Return to LP
        if (inAmount > 0) {
            bool success = transferViaProxy(
                address(betLockBox),
                tokenAdd,
                address(lp),
                inAmount
            );
            if (!success) {
                revert PayoutFailed({
                    receiver: address(lp),
                    tokenAdd: tokenAdd,
                    amount: inAmount
                });
            }
        }
    }

    /**
     * @notice Match bet, transfer tokens from the LP box to the bet box.
     * @param marketHash is the hash used to identify the market.
     * @param tokenAdd The address of the token type.
     * @param matchedAmount The amount to match the bet.
     */
    function matchBet(
        bytes32 marketHash,
        address tokenAdd,
        uint256 matchedAmount
    )
        private
    {
        lp.matchBet(tokenAdd, matchedAmount);
        // market hash => token => amount matched
        marketMatched[marketHash][tokenAdd] += matchedAmount;
    }

    /*
      * @notice Transfers a token using TokenTransferProxy.transferFrom().
      * @param from Address transfering token.
      * @param tokenAdd Address of token to transferFrom.
      * @param to Address receiving token.
      * @param value Amount of token to transfer.
      * @return Success of token transfer.
      */
    function transferViaProxy(
        address from,
        address tokenAdd,
        address to,
        uint256 value
    )
        private
        returns (bool)
    {
        return tokenTransferProxy.transferFrom(tokenAdd, from, to, value);
    }
}


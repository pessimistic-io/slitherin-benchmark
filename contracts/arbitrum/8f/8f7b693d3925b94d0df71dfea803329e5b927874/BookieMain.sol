// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IBookieMain.sol";
import "./AccessHandler.sol";
import "./LibString.sol";
import "./BetData.sol";
import "./TokenAmountValidator.sol";
// For debugging only


/**
 * @title Bookie Main contract
 * @author Deepp Dev Team
 * @notice This is the main contract for the app: BookieMain.
 * @notice Multi contract app taking bets and locking tokens until bets settle.
 * @notice Token bets are matched from a liquidity pool (LP) of same token type.
 * @notice The LP holds tokens of a certain type, and issues LP tokens as
 *         proof of deposit.
 * @notice It has a simple node.js react app for easy interfacing.
 * @notice Accesshandler is Initializable.
 */
contract BookieMain is IBookieMain, AccessHandler {

    using TokenAmountValidator for address;
    using LibString for string;

    IBetHelper private lp;
    IBetHistory private betHistory;
    IMarketHistory private marketHistory;
    IBonusDistribution private bonusHandler;
    ITokenTransferProxy private tokenTransferProxy; // Just used as an address

    /**
     * @notice Event that fires when a bet is accepted.
     * @param better is the address that made the bet.
     * @param betHash is calculated hash of the bet data.
     * @param marketHash is the hash of the market betted.
     * @param amount is the betters amount wagered.
     * @param token is the token contract address.
     * @param decimalOdds is the odds of the bet in decimal format.
     */
    event BetWagered(
        address indexed better,
        bytes32 indexed betHash,
        bytes32 indexed marketHash,
        uint256 amount,
        address token,
        uint256 decimalOdds
    );

    /**
     * @notice Event that fires when a bet is decided/settled.
     * @param better is the address that won the bet.
     * @param betHash is calculated hash of the bet data.
     * @param token is the token contract address
     * @param paid is the prize paid out (0 if its a loss).
     */
    event BetSettled(
        address indexed better,
        bytes32 indexed betHash,
        address token,
        uint256 paid
    );

    /**
     * @notice Event that fires when a bet is canceled.
     *         Can be due to a canceled market or an admin action.
     * @param better is the address made the bet.
     * @param betHash is calculated hash of the bet data.
     * @param token is the token contract address
     * @param paid is the amount paid back.
     */
    event BetCanceled(
        address indexed better,
        bytes32 indexed betHash,
        address token,
        uint256 paid
    );

    /**
     * @notice Event fires when there is no bet to settle.
     * @param better is the owner of the bet.
     * @param betHash is calculated hash of the bet data.
     */
    event BetNothingToSettle(
        address indexed better,
        bytes32 indexed betHash
    );

    /**
     * @notice Event fires there is no bet to cancel
     * @param better is the owner of the bet.
     * @param betHash is calculated hash of the bet data.
     */
    event BetNothingToCancel(
        address indexed better,
        bytes32 indexed betHash
    );

    /**
     * @notice Error for Insufficient user balance for betting.
     *         Needed `required` but only `available` available.
     * @param available balance available.
     * @param required requested amount to bet.
     */
    error InsufficientBalance(uint256 available, uint256 required);

    /**
     * @notice Error for Insufficient allowance for betting.
     *         Needed `required` but only `available` available.
     * @param available allowance available.
     * @param required requested amount to bet.
     */
    error InsufficientAllowance(uint256 available, uint256 required);

    /**
     * @notice Error for Insufficient liquidity to match a bet.
     * Needed `required` but only `available` available.
     * @param available balance available.
     * @param required requested amount to transfer.
     */
    error InsufficientLiquidityBalance(uint256 available, uint256 required);

    /**
     * @notice Error for Invaid bet.
     * @param reason is the reason of the error.
     * @param bet is the bet details.
     */
    error InvalidBet(string reason, BetData.Bet bet);

    /**
     * @notice Error for a non matching signature.
     * @param betHash is the calculated hash of the bet details.
     */
    error InvalidSignature(bytes32 betHash);

    constructor() AccessHandler() {}

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inLP The Liquidity Pool contract address, for matching bets.
     * @param inBetHistory The bet history contract address for storing bets.
     * @param inMarketHistory The market history contract address.
     * @param inTokenTransferProxy The TokenTransferProxy contract address.
     */
    function init(
        IBetHelper inLP,
        IBetHistory inBetHistory,
        IMarketHistory inMarketHistory,
        IBonusDistribution inBonusDistribution,
        ITokenTransferProxy inTokenTransferProxy
    )
        external
        notInitialized
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        lp = inLP;
        betHistory = inBetHistory;
        marketHistory = inMarketHistory;
        bonusHandler = inBonusDistribution;
        tokenTransferProxy = inTokenTransferProxy;
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
     * @notice Setter to change the referenced BetHistory contract.
     * @param inBetHistory The bet history contract for storing bets.
     */
    function setBetHistory(IBetHistory inBetHistory)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        betHistory = inBetHistory;
    }

    /**
     * @notice Setter to change the referenced MarketHistory contract.
     * @param inMarketHistory The market history contract address.
     */
    function setMarketHistory(IMarketHistory inMarketHistory)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        marketHistory = inMarketHistory;
    }

    /**
     * @notice Setter to change the referenced BonusDistribution contract.
     * @param inBonusDistribution The bonus handler contract address.
     */
    function setBonusDistribution(IBonusDistribution inBonusDistribution)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bonusHandler = inBonusDistribution;
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
     * @notice Check bet data and signature against a stored signer account.
     *         Create the bet if it validates.
     * @param token The token type to bet.
     * @param amount The amount to bet.
     * @param odds The odds of the bet in decimal notation.
     * @param expiry The epoch representation of expiry time of the request.
     * @param marketHash Is the market hash to identify the market.
     * @param signature The signature to compare to the signer.
     */
    function makeBet(
        address token,
        uint256 amount,
        uint256 odds,
        uint256 expiry,
        bytes32 marketHash,
        bytes calldata signature
    )
        external
        override
        isInitialized
        whenNotPaused
    {
        address better = msg.sender;
        BetData.Bet memory bet = BetData.Bet({
            marketHash: marketHash,
            token: token,
            amount: amount,
            decimalOdds: odds,
            expiry: expiry,
            owner: better
        });






            bytes32 betHash = BetData.getBetHash(bet);
            if (!hasRole(SIGNER_ROLE, ECDSA.recover(betHash, signature))) {
                revert InvalidSignature({betHash: betHash});
            }




        createBet(bet);
    }

    /**
     * @notice Creates the bet and locks the betters and the LPs tokens.
     * @param bet is a struct that holds all the bet details
     */
    function createBet(BetData.Bet memory bet) private {
        string memory validity = BetData.getParamValidity(bet);
        if (!validity.equals("OK"))
            revert InvalidBet({reason: validity, bet: bet});
        bytes32 betHash = BetData.getBetHash(bet);
        if (betHistory.getBetExists(betHash))
            revert InvalidBet({reason: "BET_ALREADY_EXISTS", bet: bet});

        // Check that its a valid market
        marketHistory.assertMarketIsActive(bet.marketHash);

        // Check balances
        (
            TokenAvailability res,
            uint256 available
        ) = bet.owner.checkAllowanceAndBalance(
            bet.amount,
            bet.token,
            address(tokenTransferProxy)
        );
        if (res == TokenAvailability.InsufficientBalance) {
            revert InsufficientBalance({
                available: available,
                required: bet.amount
            });
        } else if (res == TokenAvailability.InsufficientAllowance) {
            revert InsufficientAllowance({
                available: available,
                required: bet.amount
            });
        }

        uint256 liquidityBetBalance = lp.getLiquidityAvailableForBet(bet.token);
        uint256 matchedAmount = (bet.amount * bet.decimalOdds / BetData.ODDS_PRECISION) - bet.amount;

        if (liquidityBetBalance < matchedAmount) {
            revert InsufficientLiquidityBalance({
                available: liquidityBetBalance,
                required: matchedAmount
            });
        }

        //Now match, persist, transfer and token-lock the bet
        betHistory.createBet(bet);
        // Report the bet to the bonus handler
        if (address(bonusHandler) != address(0))
            bonusHandler.updateProgress(bet.owner, bet.amount);

        emit BetWagered(
            bet.owner,
            betHash,
            bet.marketHash,
            bet.amount,
            bet.token,
            bet.decimalOdds);
    }


    /**
     * @notice Settle a bet and pay the pot to the winner or to our LP
     * @param betHash The key/hash of the bet settle.
     */
    function settleBet(bytes32 betHash) external override whenNotPaused {
        BetData.BetSettleResult memory res = betHistory.settleBet(betHash);

        if (res.paidToBetter == 0 && res.paidToLP == 0) {
            emit BetNothingToSettle(res.better, betHash);
            return;
        }




        emit BetSettled(res.better, betHash, res.tokenAdd, res.paidToBetter);
    }

   /**
     * @notice Let the admin of this contract cancel an active bet
     * @param betHash The key/hash of the bet cancel.
     */
    function cancelBetAsAdmin(bytes32 betHash)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        BetData.BetSettleResult memory res = betHistory.cancelBet(betHash);

        if (res.paidToBetter == 0 && res.paidToLP == 0) {
            emit BetNothingToCancel(res.better, betHash);
            return;
        }
        emit BetCanceled(
            res.better,
            betHash,
            res.tokenAdd,
            res.paidToBetter
        );
    }
}


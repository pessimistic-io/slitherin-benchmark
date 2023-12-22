// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./Protocol.sol";
import "./PriceFeed.sol";
import "./BeyondPricer.sol";
import "./OptionCatalogue.sol";

import "./ERC20.sol";
import "./Types.sol";
import "./ReentrancyGuard.sol";
import "./CustomErrors.sol";
import "./AccessControl.sol";
import "./OptionsCompute.sol";
import "./SafeTransferLib.sol";
import "./OpynInteractions.sol";

import "./IWhitelist.sol";
import "./ILiquidityPool.sol";
import "./IHedgingReactor.sol";
import "./IOptionRegistry.sol";
import "./OtokenInterface.sol";
import "./AddressBookInterface.sol";
import "./IAlphaPortfolioValuesFeed.sol";

import "./RyskActions.sol";
import "./CombinedActions.sol";

import "./PRBMathSD59x18.sol";
import "./PRBMathUD60x18.sol";

import "./Pausable.sol";
import "./ISwapRouter.sol";
import { IOtoken, IController } from "./GammaInterface.sol";

/**
 *  @title Contract used for all user facing options interactions
 *  @dev Interacts with liquidityPool to write options and quote their prices.
 */
contract OptionExchange is Pausable, AccessControl, ReentrancyGuard, IHedgingReactor {
	using PRBMathSD59x18 for int256;
	using PRBMathUD60x18 for uint256;

	///////////////////////////
	/// immutable variables ///
	///////////////////////////

	// Liquidity pool contract
	ILiquidityPool public immutable liquidityPool;
	// protocol management contract
	Protocol public immutable protocol;
	// asset that denominates the strike price
	address public immutable strikeAsset;
	// asset that is used as the reference asset
	address public immutable underlyingAsset;
	// asset that is used for collateral asset
	address public immutable collateralAsset;
	/// @notice address book used for the gamma protocol
	AddressBookInterface public immutable addressbook;
	/// @notice instance of the uniswap V3 router interface
	ISwapRouter public immutable swapRouter;

	/////////////////////////////////////
	/// governance settable variables ///
	/////////////////////////////////////

	// pricer contract used for pricing options
	BeyondPricer public pricer;
	/// @notice pool fees for different swappable assets
	mapping(address => uint24) public poolFees;
	/// @notice fee recipient
	address public feeRecipient;
	/// @notice option catalogue
	OptionCatalogue public catalogue;
	/// @notice maximum amount allowed for a single trade
	uint256 public maxTradeSize = 1000e18;
	/// @notice minimum amount allowed for a single trade
	uint256 public minTradeSize = 1e16;
	/// @notice mapping of approved collateral for puts and calls
	mapping(address => mapping(bool => bool)) public approvedCollateral;

	///////////////////////////
	/// transient variables ///
	///////////////////////////

	// user -> token addresses interacted with in this transaction
	mapping(address => address[]) internal tempTokenQueue;
	// user -> token address -> amount
	mapping(address => mapping(address => uint256)) public heldTokens;

	//////////////////////////
	/// constant variables ///
	//////////////////////////

	/// @notice max bips used for percentages
	uint256 private constant MAX_BIPS = 10_000;
	// oToken decimals
	uint8 private constant OPYN_DECIMALS = 8;
	// scale otoken conversion decimals
	uint8 private constant CONVERSION_DECIMALS = 10;
	/// @notice used for unlimited token approval
	uint256 private constant MAX_UINT = 2 ** 256 - 1;

	/////////////////////////
	/// structs && events ///
	/////////////////////////

	struct SellParams {
		address seriesAddress;
		Types.OptionSeries seriesToStore;
		Types.OptionSeries optionSeries;
		uint256 premium;
		int256 delta;
		uint256 fee;
		uint256 amount;
		uint256 tempHoldings;
		uint256 transferAmount;
		uint256 premiumSent;
	}

	struct BuyParams {
		address seriesAddress;
		Types.OptionSeries seriesToStore;
		Types.OptionSeries optionSeries;
		uint128 strikeDecimalConverted;
		uint256 premium;
		int256 delta;
		uint256 fee;
	}

	event OptionsIssued(address indexed series);
	event OptionsBought(
		address indexed series,
		address indexed buyer,
		uint256 optionAmount,
		uint256 premium,
		uint256 fee
	);
	event OptionsSold(
		address indexed series,
		address indexed seller,
		uint256 optionAmount,
		uint256 premium,
		uint256 fee
	);
	event OptionsRedeemed(
		address indexed series,
		uint256 optionAmount,
		uint256 redeemAmount,
		address redeemAsset
	);
	event RedemptionSent(uint256 redeemAmount, address redeemAsset, address recipient);
	event OtokenMigrated(address newOptionExchange, address otoken, uint256 amount);

	error TradeTooSmall();
	error TradeTooLarge();
	error PoolFeeNotSet();
	error TokenImbalance();
	error NothingToClose();
	error PremiumTooSmall();
	error ForbiddenAction();
	error CloseSizeTooLarge();
	error UnauthorisedSender();
	error OperatorNotApproved();
	error TooMuchSlippage();

	constructor(
		address _authority,
		address _protocol,
		address _liquidityPool,
		address _pricer,
		address _addressbook,
		address _swapRouter,
		address _feeRecipient,
		address _catalogue
	) AccessControl(IAuthority(_authority)) {
		protocol = Protocol(_protocol);
		liquidityPool = ILiquidityPool(_liquidityPool);
		collateralAsset = liquidityPool.collateralAsset();
		underlyingAsset = liquidityPool.underlyingAsset();
		strikeAsset = liquidityPool.strikeAsset();
		addressbook = AddressBookInterface(_addressbook);
		swapRouter = ISwapRouter(_swapRouter);
		pricer = BeyondPricer(_pricer);
		catalogue = OptionCatalogue(_catalogue);
		feeRecipient = _feeRecipient;
	}

	///////////////
	/// setters ///
	///////////////

	function pause() external {
		_onlyGuardian();
		_pause();
	}

	function unpause() external {
		_onlyGuardian();
		_unpause();
	}

	/**
	 * @notice change the pricer
	 */
	function setPricer(address _pricer) external {
		_onlyGovernor();
		pricer = BeyondPricer(_pricer);
	}

	/**
	 * @notice change the catalogue
	 */
	function setOptionCatalogue(address _catalogue) external {
		_onlyGovernor();
		catalogue = OptionCatalogue(_catalogue);
	}

	/**
	 * @notice change the fee recipient
	 */
	function setFeeRecipient(address _feeRecipient) external {
		_onlyGovernor();
		feeRecipient = _feeRecipient;
	}

	/// @notice set the uniswap v3 pool fee for a given asset, also give the asset max approval on the uni v3 swap router
	function setPoolFee(address asset, uint24 fee) external {
		_onlyGovernor();
		poolFees[asset] = fee;
		SafeTransferLib.safeApprove(ERC20(asset), address(swapRouter), MAX_UINT);
	}

	/// @notice set the maximum and minimum trade size
	function setTradeSizeLimits(uint256 _minTradeSize, uint256 _maxTradeSize) external {
		_onlyGovernor();
		minTradeSize = _minTradeSize;
		maxTradeSize = _maxTradeSize;
	}

	/// @notice set whether a collateral is approved for selling to the vault
	function changeApprovedCollateral(address collateral, bool isPut, bool isApproved) external {
		_onlyGovernor();
		approvedCollateral[collateral][isPut] = isApproved;
	}

	//////////////////////////////////////////////////////
	/// access-controlled state changing functionality ///
	//////////////////////////////////////////////////////

	/// @inheritdoc IHedgingReactor
	function withdraw(uint256 _amount) external returns (uint256) {
		require(msg.sender == address(liquidityPool));
		address _token = collateralAsset;
		// check the holdings if enough just lying around then transfer it
		uint256 balance = ERC20(_token).balanceOf(address(this));
		if (balance == 0) {
			return 0;
		}
		if (_amount <= balance) {
			SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, _amount);
			// return in collat decimals format
			return _amount;
		} else {
			SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, balance);
			// return in collatDecimals format
			return balance;
		}
	}

	/**
	 * @notice get the dhv to redeem an expired otoken
	 * @param _series the list of series to redeem
	 */
	function redeem(address[] memory _series, uint256[] memory amountOutMinimums) external {
		_onlyManager();
		uint256 adLength = _series.length;
		if (adLength != amountOutMinimums.length) revert CustomErrors.InvalidInput();
		for (uint256 i; i < adLength; i++) {
			// get the number of otokens held by this address for the specified series
			uint256 optionAmount = ERC20(_series[i]).balanceOf(address(this));
			IOtoken otoken = IOtoken(_series[i]);
			// redeem from opyn to this address
			uint256 redeemAmount = OpynInteractions.redeemToAddress(
				addressbook.getController(),
				addressbook.getMarginPool(),
				_series[i],
				optionAmount,
				address(this)
			);

			address otokenCollateralAsset = otoken.collateralAsset();
			emit OptionsRedeemed(_series[i], optionAmount, redeemAmount, otokenCollateralAsset);
			// if the collateral used by the otoken is the collateral asset then transfer the redemption to the liquidity pool
			// if the collateral used by the otoken is anything else (or if underlying and sellRedemptions is true) then swap it on uniswap and send the proceeds to the liquidity pool
			if (otokenCollateralAsset == collateralAsset) {
				SafeTransferLib.safeTransfer(ERC20(collateralAsset), address(liquidityPool), redeemAmount);
				emit RedemptionSent(redeemAmount, collateralAsset, address(liquidityPool));
			} else {
				uint256 redeemableCollateral = _swapExactInputSingle(
					redeemAmount,
					amountOutMinimums[i],
					otokenCollateralAsset
				);
				SafeTransferLib.safeTransfer(
					ERC20(collateralAsset),
					address(liquidityPool),
					redeemableCollateral
				);
				emit RedemptionSent(redeemableCollateral, collateralAsset, address(liquidityPool));
			}
		}
	}

	/**
	 * @notice transfer otokens held by this address to a new option exchange or to the option handler
	 * @param newOptionExchange the option exchange to migrate to or handler
	 * @param otokens the otoken addresses to transfer
	 */
	function transferOtokens(address newOptionExchange, address[] memory otokens) external {
		_onlyGovernor();
		uint256 len = otokens.length;
		for (uint256 i = 0; i < len; i++) {
			if (OtokenInterface(otokens[i]).underlyingAsset() != underlyingAsset) {
				revert CustomErrors.NonWhitelistedOtoken();
			}
			uint256 balance = ERC20(otokens[i]).balanceOf(address(this));
			SafeTransferLib.safeTransfer(ERC20(otokens[i]), newOptionExchange, balance);
			emit OtokenMigrated(newOptionExchange, otokens[i], balance);
		}
	}

	/////////////////////////////////////////////
	/// external state changing functionality ///
	/////////////////////////////////////////////

	/**
	 * @notice create an otoken, distinguished from issue because we may not want this option on the option registry
	 * @param optionSeries - otoken to create (strike in e18)
	 * @return series the address of the otoken created
	 */
	function createOtoken(Types.OptionSeries memory optionSeries) external returns (address series) {
		// deploy an oToken contract address
		// assumes strike is passed in e18, converts to e8
		uint128 formattedStrike = uint128(
			OptionsCompute.formatStrikePrice(optionSeries.strike, collateralAsset)
		);
		// check for an opyn oToken if it doesn't exist deploy it
		series = OpynInteractions.getOrDeployOtoken(
			address(addressbook.getOtokenFactory()),
			optionSeries.collateral,
			optionSeries.underlying,
			optionSeries.strikeAsset,
			formattedStrike,
			optionSeries.expiration,
			optionSeries.isPut
		);
	}

	/**
	 * @notice entry point to the contract for users, takes a queue of actions for both opyn and rysk and executes them sequentially
	 * @param  _operationProcedures an array of actions to be executed sequentially
	 */
	function operate(
		CombinedActions.OperationProcedures[] memory _operationProcedures
	) external nonReentrant whenNotPaused {
		_runActions(_operationProcedures);
		_verifyFinalState();
	}

	//////////////////////////////////
	/// primary internal functions ///
	//////////////////////////////////

	function _runActions(CombinedActions.OperationProcedures[] memory _operationProcedures) internal {
		for (uint256 i = 0; i < _operationProcedures.length; i++) {
			CombinedActions.OperationProcedures memory operationProcedure = _operationProcedures[i];
			CombinedActions.OperationType operation = operationProcedure.operation;
			if (operation == CombinedActions.OperationType.OPYN) {
				_runOpynActions(operationProcedure.operationQueue);
			} else if (operation == CombinedActions.OperationType.RYSK) {
				_runRyskActions(operationProcedure.operationQueue);
			}
		}
	}

	/**
	 * @notice verify all final state
	 */
	function _verifyFinalState() internal {
		address[] memory interactedTokens = tempTokenQueue[msg.sender];
		uint256 arr = interactedTokens.length;
		for (uint256 i = 0; i < arr; i++) {
			uint256 tempTokens = heldTokens[msg.sender][interactedTokens[i]];
			if (tempTokens != 0) {
				if (interactedTokens[i] == collateralAsset) {
					SafeTransferLib.safeTransfer(ERC20(collateralAsset), msg.sender, tempTokens);
					heldTokens[msg.sender][interactedTokens[i]] = 0;
				} else {
					revert TokenImbalance();
				}
			}
		}
		delete tempTokenQueue[msg.sender];
	}

	function _runOpynActions(CombinedActions.ActionArgs[] memory _opynActions) internal {
		IController controller = IController(addressbook.getController());
		uint256 arr = _opynActions.length;
		IController.ActionArgs[] memory _opynArgs = new IController.ActionArgs[](arr);
		// users need to have this contract approved as an operator so it can carry out actions on the user's behalf
		if (!controller.isOperator(msg.sender, address(this))) {
			revert OperatorNotApproved();
		}
		for (uint256 i = 0; i < arr; i++) {
			// loop through the opyn actions, if any involve opening a vault then make sure the msg.sender gets the ownership and if there are any more vault ids make sure the msg.sender is the owners
			IController.ActionArgs memory action = CombinedActions._parseOpynArgs(_opynActions[i]);
			IController.ActionType actionType = action.actionType;
			// make sure the owner parameter being sent in is the msg.sender this makes sure senders arent messing around with other vaults
			if (action.owner != msg.sender) {
				revert UnauthorisedSender();
			}
			if (actionType == IController.ActionType.DepositLongOption) {
				if (action.secondAddress != msg.sender) {
					revert UnauthorisedSender();
				}
			} else if (actionType == IController.ActionType.OpenVault) {
				// check the from address to make sure it comes from the user or if we are holding them temporarily then they are held here
			} else if (actionType == IController.ActionType.WithdrawLongOption) {
				// check the to address to see whether it is being sent to the user or held here temporarily
				if (action.secondAddress == address(this)) {
					_updateTempHoldings(action.asset, action.amount * 10 ** CONVERSION_DECIMALS);
				}
			} else if (actionType == IController.ActionType.DepositCollateral) {
				// check the from address is the msg.sender so the sender cant take collat from elsewhere
				if (action.secondAddress != msg.sender && action.secondAddress != address(this)) {
					revert UnauthorisedSender();
				}
				// if the address is this address then for UX purposes the collateral will be handled here
				// (this means the user only needs to do one approval for collateral to this address)
				if (action.secondAddress == address(this)) {
					SafeTransferLib.safeTransferFrom(action.asset, msg.sender, address(this), action.amount);
					// approve the margin pool from this account
					SafeTransferLib.safeApprove(ERC20(action.asset), addressbook.getMarginPool(), action.amount);
				}
			} else if (actionType == IController.ActionType.MintShortOption) {
				if (action.secondAddress == address(this)) {
					_updateTempHoldings(action.asset, action.amount * 10 ** CONVERSION_DECIMALS);
				}
				// check the to address to see whether it is being sent to the user or held here temporarily
			} else if (actionType == IController.ActionType.BurnShortOption) {
				if (action.secondAddress != msg.sender) {
					revert UnauthorisedSender();
				}
			} else if (actionType == IController.ActionType.WithdrawCollateral) {
				if (action.secondAddress != msg.sender) {
					revert UnauthorisedSender();
				}
			} else if (actionType == IController.ActionType.SettleVault) {
				if (action.secondAddress != msg.sender) {
					revert UnauthorisedSender();
				}
			} else {
				revert ForbiddenAction();
			}
			_opynArgs[i] = action;
		}
		controller.operate(_opynArgs);
	}

	function _runRyskActions(CombinedActions.ActionArgs[] memory _ryskActions) internal {
		for (uint256 i = 0; i < _ryskActions.length; i++) {
			// loop through the rysk actions
			RyskActions.ActionArgs memory action = CombinedActions._parseRyskArgs(_ryskActions[i]);
			RyskActions.ActionType actionType = action.actionType;
			if (actionType == RyskActions.ActionType.Issue) {
				_issue(RyskActions._parseIssueArgs(action));
			} else if (actionType == RyskActions.ActionType.BuyOption) {
				_buyOption(RyskActions._parseBuyOptionArgs(action));
			} else if (actionType == RyskActions.ActionType.SellOption) {
				_sellOption(RyskActions._parseSellOptionArgs(action), false);
			} else if (actionType == RyskActions.ActionType.CloseOption) {
				_sellOption(RyskActions._parseSellOptionArgs(action), true);
			}
		}
	}

	/**
	 * @notice issue an otoken that the dhv can now sell to buyers
	 * @param _args RyskAction struct containing details on the option to issue
	 * @return series the address of the option activated for selling by the dhv
	 */
	function _issue(RyskActions.IssueArgs memory _args) internal returns (address series) {
		// format the strike correctly
		uint128 strike = uint128(
			OptionsCompute.formatStrikePrice(_args.optionSeries.strike, collateralAsset) *
				10 ** CONVERSION_DECIMALS
		);
		// check if the option series is approved
		bytes32 oHash = keccak256(
			abi.encodePacked(_args.optionSeries.expiration, strike, _args.optionSeries.isPut)
		);
		OptionCatalogue.OptionStores memory optionStore = catalogue.getOptionStores(oHash);
		if (!optionStore.approvedOption) {
			revert CustomErrors.UnapprovedSeries();
		}
		// check if the series is buyable
		if (!optionStore.isBuyable) {
			revert CustomErrors.SeriesNotBuyable();
		}
		if (_args.optionSeries.strikeAsset != _args.optionSeries.collateral) {
			revert CustomErrors.CollateralAssetInvalid();
		}
		series = liquidityPool.handlerIssue(_args.optionSeries);
		emit OptionsIssued(series);
	}

	/**
	 * @notice function that allows a user to buy options from the dhv where they pay the dhv using the collateral asset
	 * @param _args RyskAction struct containing details on the option to buy
	 */
	function _buyOption(RyskActions.BuyOptionArgs memory _args) internal {
		if (_args.amount < minTradeSize) revert TradeTooSmall();
		if (_args.amount > maxTradeSize) revert TradeTooLarge();
		// get the option details in the correct formats
		IOptionRegistry optionRegistry = getOptionRegistry();
		IAlphaPortfolioValuesFeed portfolioValuesFeed = getPortfolioValuesFeed();
		BuyParams memory buyParams;
		bytes32 oHash;
		(buyParams.seriesAddress, buyParams.seriesToStore, buyParams.optionSeries, oHash) = _preChecks(
			_args.seriesAddress,
			_args.optionSeries,
			optionRegistry,
			false
		);
		address recipient = _args.recipient;
		// calculate premium and delta from the option pricer, returning the premium in collateral decimals and delta in e18
		(buyParams.premium, buyParams.delta, buyParams.fee) = pricer.quoteOptionPrice(
			buyParams.seriesToStore,
			_args.amount,
			false,
			portfolioValuesFeed.netDhvExposure(oHash)
		);
		if (buyParams.premium > _args.acceptablePremium) {
			revert TooMuchSlippage();
		}
		_handlePremiumTransfer(buyParams.premium, buyParams.fee);
		// get what the exchange's balance is on this asset, as this can be used instead of the dhv having to lock up collateral
		uint256 longExposure = ERC20(buyParams.seriesAddress).balanceOf(address(this)) *
			10 ** CONVERSION_DECIMALS;
		uint256 amount = _args.amount;
		emit OptionsBought(buyParams.seriesAddress, recipient, amount, buyParams.premium, buyParams.fee);
		if (longExposure > 0) {
			// calculate the maximum amount that should be bought by the user
			uint256 boughtAmount = longExposure > amount ? amount : uint256(longExposure);
			// transfer the otokens to the user
			SafeTransferLib.safeTransfer(
				ERC20(buyParams.seriesAddress),
				recipient,
				boughtAmount / (10 ** CONVERSION_DECIMALS)
			);
			// update the series on the stores
			portfolioValuesFeed.updateStores(
				buyParams.seriesToStore,
				0,
				-int256(boughtAmount),
				buyParams.seriesAddress
			);
			liquidityPool.adjustVariables(
				0,
				buyParams.premium.mul(boughtAmount).div(_args.amount),
				buyParams.delta.mul(int256(boughtAmount)).div(int256(_args.amount)),
				true
			);
			amount -= boughtAmount;
			if (amount == 0) {
				return;
			}
		}
		if (buyParams.optionSeries.collateral != collateralAsset) {
			revert CustomErrors.CollateralAssetInvalid();
		}
		// add this series to the portfolio values feed so its stored on the book
		portfolioValuesFeed.updateStores(
			buyParams.seriesToStore,
			int256(amount),
			0,
			buyParams.seriesAddress
		);
		// get the liquidity pool to write the options
		liquidityPool.handlerWriteOption(
			buyParams.optionSeries,
			buyParams.seriesAddress,
			amount,
			optionRegistry,
			buyParams.premium.mul(amount).div(_args.amount),
			buyParams.delta.mul(int256(amount)).div(int256(_args.amount)),
			recipient
		);
	}

	/**
	 * @notice function that allows a user to sell options to the dhv and pays them a premium in the vaults collateral asset
	 * @param _args RyskAction struct containing details on the option to sell
	 * @param isClose if true then we only close positions the dhv has open, we do not conduct any more sales beyond that
	 */
	function _sellOption(RyskActions.SellOptionArgs memory _args, bool isClose) internal {
		if (_args.amount < minTradeSize) revert TradeTooSmall();
		if (_args.amount > maxTradeSize) revert TradeTooLarge();
		IOptionRegistry optionRegistry = getOptionRegistry();
		IAlphaPortfolioValuesFeed portfolioValuesFeed = getPortfolioValuesFeed();
		SellParams memory sellParams;
		bytes32 oHash;
		(sellParams.seriesAddress, sellParams.seriesToStore, sellParams.optionSeries, oHash) = _preChecks(
			_args.seriesAddress,
			_args.optionSeries,
			optionRegistry,
			true
		);
		// get the unit price for premium and delta
		(sellParams.premium, sellParams.delta, sellParams.fee) = pricer.quoteOptionPrice(
			sellParams.seriesToStore,
			_args.amount,
			true,
			portfolioValuesFeed.netDhvExposure(oHash)
		);
		if (sellParams.premium < _args.acceptablePremium) {
			revert TooMuchSlippage();
		}
		sellParams.amount = _args.amount;
		sellParams.tempHoldings = OptionsCompute.min(
			heldTokens[msg.sender][sellParams.seriesAddress],
			_args.amount
		);
		heldTokens[msg.sender][sellParams.seriesAddress] -= sellParams.tempHoldings;
		int256 shortExposure = portfolioValuesFeed
			.storesForAddress(sellParams.seriesAddress)
			.shortExposure;
		if (shortExposure > 0) {
			// if they are just closing and the amount to close is bigger than the dhv's position then we revert
			if (isClose && OptionsCompute.toInt256(sellParams.amount) > shortExposure) {
				revert CloseSizeTooLarge();
			}
			sellParams = _handleDHVBuyback(sellParams, shortExposure, optionRegistry);
		} else if (isClose) {
			// if they are closing and there is nothing to close then we revert
			revert NothingToClose();
		}
		// if they are not closing and the premium / 8 is less than or equal to the fee then we revert
		// because the sale doesnt make sense
		if (!isClose && (sellParams.premium >> 3) <= sellParams.fee) {
			revert PremiumTooSmall();
		}
		if (sellParams.amount > 0) {
			if (sellParams.amount > sellParams.tempHoldings) {
				// transfer the otokens to this exchange
				SafeTransferLib.safeTransferFrom(
					sellParams.seriesAddress,
					msg.sender,
					address(this),
					OptionsCompute.convertToDecimals(
						sellParams.amount - sellParams.tempHoldings,
						ERC20(sellParams.seriesAddress).decimals()
					)
				);
			}
			// update on the pvfeed stores
			portfolioValuesFeed.updateStores(
				sellParams.seriesToStore,
				0,
				int256(sellParams.amount),
				sellParams.seriesAddress
			);
			liquidityPool.adjustVariables(
				0,
				sellParams.premium.mul(sellParams.amount).div(_args.amount),
				sellParams.delta.mul(int256(sellParams.amount)).div(int256(_args.amount)),
				false
			);
		}
		// this accounts for premium sent from buyback as well as any rounding errors from the dhv buyback
		if (sellParams.premium > sellParams.premiumSent) {
			// we need to make sure we arent eating into the withdraw partition or the liquidity buffer with this trade
			if (ILiquidityPool(liquidityPool).checkBuffer() < int256((sellParams.premium - sellParams.premiumSent))) {
				revert CustomErrors.MaxLiquidityBufferReached();
		}
			// take the funds from the liquidity pool and pay them here
			SafeTransferLib.safeTransferFrom(
				collateralAsset,
				address(liquidityPool),
				address(this),
				sellParams.premium - sellParams.premiumSent
			);
		}
		// transfer any fees
		// bitshift to the right 3 times to get to 1/8
		if ((sellParams.premium >> 3) > sellParams.fee) {
			SafeTransferLib.safeTransfer(ERC20(collateralAsset), feeRecipient, sellParams.fee);
		} else {
			// if the total fee is greater than premium / 8 then the fee is capped at , this is to avoid disincentivising selling back to the pool for collateral release
			sellParams.fee = sellParams.premium >> 3;
			SafeTransferLib.safeTransfer(ERC20(collateralAsset), feeRecipient, sellParams.fee);
		}
		// if the recipient is this address then update the temporary holdings now to indicate the premium is temporarily being held here
		if (_args.recipient == address(this)) {
			_updateTempHoldings(collateralAsset, sellParams.premium - sellParams.fee);
		} else {
			// transfer premium to the recipient
			SafeTransferLib.safeTransfer(
				ERC20(collateralAsset),
				_args.recipient,
				sellParams.premium - sellParams.fee
			);
		}
		emit OptionsSold(
			sellParams.seriesAddress,
			_args.recipient,
			_args.amount,
			sellParams.premium,
			sellParams.fee
		);
	}

	///////////////////////////
	/// non-complex getters ///
	///////////////////////////

	/**
	 * @notice get the option registry used for storing and managing the options
	 * @return the option registry contract
	 */
	function getOptionRegistry() internal view returns (IOptionRegistry) {
		return IOptionRegistry(protocol.optionRegistry());
	}

	/**
	 * @notice get the portfolio values feed used by the liquidity pool
	 * @return the portfolio values feed contract
	 */
	function getPortfolioValuesFeed() internal view returns (IAlphaPortfolioValuesFeed) {
		return IAlphaPortfolioValuesFeed(protocol.portfolioValuesFeed());
	}

	/// @inheritdoc IHedgingReactor
	function getDelta() external view returns (int256 delta) {
		return 0;
	}

	/// @inheritdoc IHedgingReactor
	function getPoolDenominatedValue() external view returns (uint256) {
		return ERC20(collateralAsset).balanceOf(address(this));
	}

	function getOptionDetails(
		address seriesAddress,
		Types.OptionSeries memory optionSeries
	) external view returns (address, Types.OptionSeries memory, uint128) {
		return _getOptionDetails(seriesAddress, optionSeries, getOptionRegistry());
	}

	function checkHash(
		Types.OptionSeries memory optionSeries,
		uint128 strikeDecimalConverted,
		bool isSell
	) external view returns (bytes32 oHash) {
		return _checkHash(optionSeries, strikeDecimalConverted, isSell);
	}

	//////////////////////////
	/// internal utilities ///
	//////////////////////////

	function _getOptionDetails(
		address seriesAddress,
		Types.OptionSeries memory optionSeries,
		IOptionRegistry optionRegistry
	) internal view returns (address, Types.OptionSeries memory, uint128) {
		// if the series address is not known then we need to find it by looking for the otoken,
		// if we cant find it then it means the otoken hasnt been created yet, strike is e18
		if (seriesAddress == address(0)) {
			seriesAddress = optionRegistry.getOtoken(
				optionSeries.underlying,
				optionSeries.strikeAsset,
				optionSeries.expiration,
				optionSeries.isPut,
				optionSeries.strike,
				optionSeries.collateral
			);
			optionSeries = Types.OptionSeries(
				optionSeries.expiration,
				uint128(OptionsCompute.formatStrikePrice(optionSeries.strike, collateralAsset)),
				optionSeries.isPut,
				optionSeries.underlying,
				optionSeries.strikeAsset,
				optionSeries.collateral
			);
		} else {
			// if the series address was passed in as non zero then we'll first check the option registry storage,
			// if its not there then we know this isnt a buyback operation
			optionSeries = optionRegistry.getSeriesInfo(seriesAddress);
			// make sure the expiry actually exists, if it doesnt then get the otoken itself
			if (optionSeries.expiration == 0) {
				IOtoken otoken = IOtoken(seriesAddress);
				// get the option details
				optionSeries = Types.OptionSeries(
					uint64(otoken.expiryTimestamp()),
					uint128(otoken.strikePrice()),
					otoken.isPut(),
					otoken.underlyingAsset(),
					otoken.strikeAsset(),
					otoken.collateralAsset()
				);
			}
		}
		if (seriesAddress == address(0)) {
			revert CustomErrors.NonExistentOtoken();
		}
		// strike is in e18
		// make sure the expiry actually exists
		if (optionSeries.expiration == 0) {
			revert CustomErrors.NonExistentOtoken();
		}
		// strikeDecimalConverted is the formatted strike price (for e8) in e18 format
		// option series returned with e8
		uint128 strikeDecimalConverted = uint128(optionSeries.strike * 10 ** CONVERSION_DECIMALS);
		// we need to make sure the seriesAddress is actually whitelisted as an otoken in case the actor wants to
		// try sending a made up otoken
		IWhitelist whitelist = IWhitelist(addressbook.getWhitelist());
		if (!whitelist.isWhitelistedOtoken(seriesAddress)) {
			revert CustomErrors.NonWhitelistedOtoken();
		}
		return (seriesAddress, optionSeries, strikeDecimalConverted);
	}

	function _checkHash(
		Types.OptionSeries memory optionSeries,
		uint128 strikeDecimalConverted,
		bool isSell
	) internal view returns (bytes32 oHash) {
		// check if the option series is approved
		oHash = keccak256(
			abi.encodePacked(optionSeries.expiration, strikeDecimalConverted, optionSeries.isPut)
		);
		OptionCatalogue.OptionStores memory optionStore = catalogue.getOptionStores(oHash);
		if (!optionStore.approvedOption) {
			revert CustomErrors.UnapprovedSeries();
		}
		if (isSell) {
			if (!optionStore.isSellable) {
				revert CustomErrors.SeriesNotSellable();
			}
		} else {
			if (!optionStore.isBuyable) {
				revert CustomErrors.SeriesNotBuyable();
			}
		}
	}

	/** @notice function to sell exact amount of assetIn to the minimum amountOutMinimum of collateralAsset
	 *  @param _amountIn the exact amount of assetIn to sell
	 *  @param _amountOutMinimum the min amount of collateral asset willing to receive. Slippage limit.
	 *  @param _assetIn the asset to swap from
	 *  @return the amount of usdc received
	 */
	function _swapExactInputSingle(
		uint256 _amountIn,
		uint256 _amountOutMinimum,
		address _assetIn
	) internal returns (uint256) {
		uint24 poolFee = poolFees[_assetIn];
		if (poolFee == 0) {
			revert PoolFeeNotSet();
		}
		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: _assetIn,
			tokenOut: collateralAsset,
			fee: poolFee,
			recipient: address(this),
			deadline: block.timestamp,
			amountIn: _amountIn,
			amountOutMinimum: _amountOutMinimum,
			sqrtPriceLimitX96: 0
		});

		// The call to `exactInputSingle` executes the swap.
		uint256 amountOut = swapRouter.exactInputSingle(params);
		return amountOut;
	}

	function _updateTempHoldings(address asset, uint256 amount) internal {
		if (heldTokens[msg.sender][asset] == 0) {
			tempTokenQueue[msg.sender].push(asset);
		}
		heldTokens[msg.sender][asset] += amount;
	}

	function _handlePremiumTransfer(uint256 premium, uint256 fee) internal {
		// check if we need to transfer anything from the user into this wallet
		if (premium + fee > heldTokens[msg.sender][collateralAsset]) {
			uint256 diff = premium + fee - heldTokens[msg.sender][collateralAsset];
			// reduce their temporary holdings to 0
			heldTokens[msg.sender][collateralAsset] = 0;
			SafeTransferLib.safeTransferFrom(collateralAsset, msg.sender, address(this), diff);
		} else {
			// reduce their temporary holdings by the premium and fee
			heldTokens[msg.sender][collateralAsset] -= premium + fee;
		}
		// handle fees
		if (fee > 0) {
			SafeTransferLib.safeTransfer(ERC20(collateralAsset), feeRecipient, fee);
		}
		// transfer premium to liquidity pool
		SafeTransferLib.safeTransfer(ERC20(collateralAsset), address(liquidityPool), premium);
	}

	function _preChecks(
		address _seriesAddress,
		Types.OptionSeries memory _optionSeries,
		IOptionRegistry _optionRegistry,
		bool isSell
	) internal view returns (address, Types.OptionSeries memory, Types.OptionSeries memory, bytes32) {
		(
			address seriesAddress,
			Types.OptionSeries memory optionSeries,
			uint128 strikeDecimalConverted
		) = _getOptionDetails(_seriesAddress, _optionSeries, _optionRegistry);
		// check the option hash and option series for validity
		bytes32 oHash = _checkHash(optionSeries, strikeDecimalConverted, isSell);
		// check details of the option series
		if (optionSeries.expiration <= block.timestamp) {
			revert CustomErrors.OptionExpiryInvalid();
		}
		if (optionSeries.underlying != underlyingAsset) {
			revert CustomErrors.UnderlyingAssetInvalid();
		}
		if (optionSeries.strikeAsset != strikeAsset) {
			revert CustomErrors.StrikeAssetInvalid();
		}
		if (!approvedCollateral[optionSeries.collateral][optionSeries.isPut]) {
			revert CustomErrors.CollateralAssetInvalid();
		}
		// convert the strike to e18 decimals for storage
		Types.OptionSeries memory seriesToStore = Types.OptionSeries(
			optionSeries.expiration,
			strikeDecimalConverted,
			optionSeries.isPut,
			underlyingAsset,
			strikeAsset,
			optionSeries.collateral
		);
		return (seriesAddress, seriesToStore, optionSeries, oHash);
	}

	function _handleDHVBuyback(
		SellParams memory sellParams,
		int256 shortExposure,
		IOptionRegistry optionRegistry
	) internal returns (SellParams memory) {
		sellParams.transferAmount = OptionsCompute.min(uint256(shortExposure), sellParams.amount);
		// will transfer any tempHoldings they have here to the liquidityPool
		if (sellParams.tempHoldings > 0) {
			SafeTransferLib.safeTransfer(
				ERC20(sellParams.seriesAddress),
				address(liquidityPool),
				OptionsCompute.convertToDecimals(
					OptionsCompute.min(sellParams.tempHoldings, sellParams.transferAmount),
					ERC20(sellParams.seriesAddress).decimals()
				)
			);
		}
		// want to check if they have any otokens in their wallet and send those here
		if (sellParams.transferAmount > sellParams.tempHoldings) {
			SafeTransferLib.safeTransferFrom(
				sellParams.seriesAddress,
				msg.sender,
				address(liquidityPool),
				OptionsCompute.convertToDecimals(
					sellParams.transferAmount - sellParams.tempHoldings,
					ERC20(sellParams.seriesAddress).decimals()
				)
			);
		}
		sellParams.premiumSent = sellParams.premium.mul(sellParams.transferAmount).div(sellParams.amount);
		uint256 soldBackAmount = liquidityPool.handlerBuybackOption(
			sellParams.optionSeries,
			sellParams.transferAmount,
			optionRegistry,
			sellParams.seriesAddress,
			sellParams.premiumSent,
			sellParams.delta.mul(OptionsCompute.toInt256(sellParams.transferAmount)).div(
				OptionsCompute.toInt256(sellParams.amount)
			),
			address(this)
		);
		// update the series on the stores
		getPortfolioValuesFeed().updateStores(
			sellParams.seriesToStore,
			-int256(soldBackAmount),
			0,
			sellParams.seriesAddress
		);
		sellParams.amount -= soldBackAmount;
		sellParams.tempHoldings -= OptionsCompute.min(sellParams.tempHoldings, sellParams.transferAmount);
		return sellParams;
	}

	///////////////////////
	/// complex getters ///
	///////////////////////

	/// @inheritdoc IHedgingReactor
	function update() external pure returns (uint256) {
		return 0;
	}

	/// @inheritdoc IHedgingReactor
	function hedgeDelta(int256 _delta) external returns (int256) {
		revert();
	}
}


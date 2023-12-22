// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./PriceFeed.sol";

import "./AccessControl.sol";
import "./OptionsCompute.sol";
import "./SafeTransferLib.sol";

import "./ILiquidityPool.sol";
import "./IHedgingReactor.sol";

import "./IClearingHouse.sol";
import "./ClearingHouseExtsload.sol";

import "./Math.sol";

import "./ISwapRouter.sol";

/**
 *  @title A hedging reactor that will manage delta by opening or closing short or long perp positions using rage trade
 *  @dev interacts with LiquidityPool via hedgeDelta, getDelta, getPoolDenominatedValue and withdraw,
 *       interacts with Rage Trade and chainlink via the change position, update and sync
 */

contract PerpHedgingReactorWithSwap is IHedgingReactor, AccessControl {
	using ClearingHouseExtsload for IClearingHouse;
	/////////////////////////////////
	/// immutable state variables ///
	/////////////////////////////////

	/// @notice address of the parent liquidity pool contract
	address public immutable parentLiquidityPool;
	/// @notice address of the price feed used for getting asset prices
	address public immutable priceFeed;
	/// @notice collateralAsset used for collateralising the pool
	address public immutable collateralAsset;
	address public immutable LPcollateralAsset;
	/// @notice address of the wETH contract
	address public immutable wETH;
	/// @notice instance of the clearing house interface
	IClearingHouse public immutable clearingHouse;
	/// @notice collateralId to be used in the perp pool
	uint32 public immutable collateralId;
	/// @notice poolId to be used in the perp pool
	uint32 public immutable poolId;
	/// @notice accountId for the perp pool
	uint256 public immutable accountId;
	/// @notice instance of the uniswap V3 router interface
	ISwapRouter public immutable swapRouter;

	/////////////////////////
	/// dynamic variables ///
	/////////////////////////

	/// @notice delta of the pool
	int256 public internalDelta;

	/////////////////////////////////////
	/// governance settable variables ///
	/////////////////////////////////////

	/// @notice address of the keeper of this pool
	mapping(address => bool) public keeper;
	/// @notice desired healthFactor of the pool
	uint256 public healthFactor = 5_000;
	/// @notice should change position also sync state
	bool public syncOnChange;

	//////////////////////////
	/// constant variables ///
	//////////////////////////

	/// @notice used for unlimited token approval
	uint256 private constant MAX_UINT = 2**256 - 1;
	/// @notice max bips
	uint256 private constant MAX_BIPS = 10_000;
	/// @notice scale up
	uint256 private constant SCALE_UP = 1e18;

	//////////////
	/// errors ///
	//////////////

	error ValueFailure();
	error IncorrectCollateral();
	error IncorrectDeltaChange();
	error InvalidTransactionNotEnoughMargin(int256 accountMarketValue, int256 totalRequiredMargin);

	constructor(
		address _clearingHouse,
		address _collateralAsset,
		address _LPcollateralAsset,
		address _wethAddress,
		address _parentLiquidityPool,
		uint32 _poolId,
		uint32 _collateralId,
		address _priceFeed,
		address _authority,
		address _swapRouter
	) AccessControl(IAuthority(_authority)) {
		clearingHouse = IClearingHouse(_clearingHouse);
		collateralAsset = _collateralAsset;
		LPcollateralAsset = _LPcollateralAsset;
		wETH = _wethAddress;
		parentLiquidityPool = _parentLiquidityPool;
		priceFeed = _priceFeed;
		poolId = _poolId;
		collateralId = _collateralId;
		// make a perp account
		accountId = clearingHouse.createAccount();
		swapRouter = ISwapRouter(_swapRouter);
		SafeTransferLib.safeApprove(ERC20(_collateralAsset), address(swapRouter), MAX_UINT);
		SafeTransferLib.safeApprove(ERC20(_LPcollateralAsset), address(swapRouter), MAX_UINT);
	}

	///////////////
	/// setters ///
	///////////////

	/// @notice update the health factor parameter
	function setHealthFactor(uint256 _healthFactor) external {
		_onlyGovernor();
		healthFactor = _healthFactor;
	}

	/// @notice update the keepers
	function setKeeper(address _keeper, bool _auth) external {
		_onlyGovernor();
		keeper[_keeper] = _auth;
	}

	/// @notice set whether changing a position should trigger a sync before updating
	function setSyncOnChange(bool _syncOnChange) external {
		_onlyGovernor();
		syncOnChange = _syncOnChange;
	}

	////////////////////////////////////////////
	/// access-controlled external functions ///
	////////////////////////////////////////////

	/// @notice function to deposit 1 wei of USDC into the margin account so that a margin account is made, cannot be
	///         be called if an account already exists
	function initialiseReactor() external {
		(IERC20 collateral, uint256 collat) = clearingHouse.getAccountCollateralInfo(accountId, collateralId);
		if (collat != 0) {
			revert();
		}
		SafeTransferLib.safeTransferFrom(collateralAsset, msg.sender, address(this), 1);
		SafeTransferLib.safeApprove(ERC20(collateralAsset), address(clearingHouse), MAX_UINT);
		clearingHouse.updateMargin(accountId, collateralId, 1);
	}

	/// @inheritdoc IHedgingReactor
	function hedgeDelta(int256 _delta) external returns (int256 deltaChange) {
		// delta is passed in as the delta that the pool has so this function must hedge the opposite
		// if delta comes in negative then the pool must go long
		// if delta comes in positive then the pool must go short
		// the signs must be flipped when going into _changePosition
		// make sure the caller is the vault
		require(msg.sender == parentLiquidityPool, "!vault");
		deltaChange = _changePosition(-_delta);
		// record the delta change internally
		internalDelta += deltaChange;
	}
	/// @inheritdoc IHedgingReactor
	function withdraw(uint256 _amount) external returns (uint256) {
		require(msg.sender == parentLiquidityPool, "!vault");
		// check the holdings if enough just lying around then transfer it
		// assume amount is passed in as collateral decimals
		uint256 balance = ERC20(collateralAsset).balanceOf(address(this));
		if (balance == 0) {
			return 0;
		}
		if (_amount <= balance) {
			_transferOut(_amount);
			// return in collateral format
			return _amount;
		} else {
			_transferOut(balance);
			// return in collateral format
			return balance;
		}
	}

	/// @notice function to poke the margin account to update the profits of the vault and also manage
	///         the collateral to safe bounds.
	/// @dev    only callable by a keeper
	function syncAndUpdate() external {
		sync();
		update();
	}

	/// @notice function to poke the margin account to update the profits of the vault
	/// @dev    only callable by a keeper
	function sync() public {
		_isKeeper();
		clearingHouse.settleProfit(accountId);
	}

	/// @inheritdoc IHedgingReactor
	function update() public returns (uint256) {
		_isKeeper();
		int256 netPosition = clearingHouse.getAccountNetTokenPosition(accountId, poolId);
		(IERC20 collateral, uint256 collat) = clearingHouse.getAccountCollateralInfo(accountId, collateralId);
		// just make sure the collateral at index 0 is correct (this is unlikely to ever fail, but should be checked)
		if (collat == 0) {
			revert IncorrectCollateral();
		}
		if (address(collateral) != collateralAsset) {
			revert IncorrectCollateral();
		}
		// we want 1 wei at all times, so if there is only 1 wei of collat and the net position is 0 then just return
		if (collat == 1 && netPosition == 0) {
			return 0;
		}
		// get the current price of the underlying asset from chainlink to be used to calculate position sizing
		uint256 currentPrice = OptionsCompute.convertToDecimals(
			PriceFeed(priceFeed).getNormalizedRate(wETH, collateralAsset),
			ERC20(collateralAsset).decimals()
		);
		// check the collateral health of positions
		// get the amount of collateral that should be expected for a given amount
		uint256 collatRequired = netPosition >= 0
			? (((uint256(netPosition) * currentPrice) / SCALE_UP) * healthFactor) / MAX_BIPS
			: (((uint256(-netPosition) * currentPrice) / SCALE_UP) * healthFactor) / MAX_BIPS;
		// if there is not enough collateral then request more
		// if there is too much collateral then return some to the pool
		if (collatRequired > collat) {
			if (ILiquidityPool(parentLiquidityPool).getBalance(LPcollateralAsset) < (collatRequired - collat)) {
				revert CustomErrors.WithdrawExceedsLiquidity();
			}
			_transferIn(collatRequired - collat);
			// deposit the collateral into the margin account
			clearingHouse.updateMargin(accountId, collateralId, int256(collatRequired - collat));
			return collatRequired - collat;
		} else if (collatRequired < collat) {
			// withdraw excess collateral from the margin account
			clearingHouse.updateMargin(accountId, collateralId, -int256(collat - collatRequired));
			_transferOut(collat - collatRequired);
			return collat - collatRequired;
		} else {
			return 0;
		}
	}

	///////////////////////
	/// complex getters ///
	///////////////////////

	/// @inheritdoc IHedgingReactor
	function getDelta() external view returns (int256 delta) {
		return internalDelta;
	}

	/// @inheritdoc IHedgingReactor
	function getPoolDenominatedValue() external view returns (uint256 value) {
		// get the account market value
		(int256 accountMarketValue,) = clearingHouse.getAccountMarketValueAndRequiredMargin(accountId, false);
		// increment any loose balance held by the pool
		value += ERC20(collateralAsset).balanceOf(address(this));
		// if there is ever a case where value is negative then something has gone very wrong and this should be dealt with
		// by the reactor manager so the transaction should revert here
		if (accountMarketValue < 0) {
			revert ValueFailure();
		}
		value += uint256(accountMarketValue);
		// value to be returned in e18
		value = OptionsCompute.convertFromDecimals(value, ERC20(collateralAsset).decimals());
	}

	/** @notice function to check the health of the margin account
     *  @return isBelowMin is the margin below the health factor
     *  @return isAboveMax is the margin above the health factor
	 *  @return health     the health factor of the account currently
	 *  @return collatToTransfer the amount of collateral required to return the margin account back to the health factor
     */
	function checkVaultHealth() external view returns (
		bool isBelowMin,
		bool isAboveMax,
		uint256 health,
		uint256 collatToTransfer
	) {
		int256 netPosition = clearingHouse.getAccountNetTokenPosition(accountId, poolId);
		(int256 accountMarketValue,) = clearingHouse.getAccountMarketValueAndRequiredMargin(accountId, false);
		(IERC20 collateral, uint256 collat) = clearingHouse.getAccountCollateralInfo(accountId, collateralId);
		if (accountMarketValue < 0) {
			revert ValueFailure();
		}
		uint256 unsignedAccountMarketValue = uint256(accountMarketValue);
		// just make sure the collateral at index 0 is correct (this is unlikely to ever fail, but should be checked)
		if (collat == 0) {
			revert IncorrectCollateral();
		}
		if (address(collateral) != collateralAsset) {
			revert IncorrectCollateral();
		}
		// we want 1 wei at all times, so if there is only 1 wei of collat and the net position is 0 then just return
		if (collat == 1 && netPosition == 0) {
			return (false, false, healthFactor, 0);
		}
		// get the current price of the underlying asset from chainlink to be used to calculate position sizing
		uint256 currentPrice = OptionsCompute.convertToDecimals(
			PriceFeed(priceFeed).getNormalizedRate(wETH, collateralAsset),
			ERC20(collateralAsset).decimals()
		);
		// check the collateral health of positions
		// get the amount of collateral that should be expected for a given amount
		health = netPosition >= 0
			? (unsignedAccountMarketValue * MAX_BIPS) / ((uint256(netPosition) * currentPrice) / SCALE_UP)
			: (unsignedAccountMarketValue * MAX_BIPS) / ((uint256(-netPosition) * currentPrice)/ SCALE_UP);
		uint256 collatRequired = netPosition >= 0
			? (((uint256(netPosition) * currentPrice) / SCALE_UP) * healthFactor) / MAX_BIPS
			: (((uint256(-netPosition) * currentPrice) / SCALE_UP) * healthFactor) / MAX_BIPS;
		// if there is not enough collateral then request more
		// if there is too much collateral then return some to the pool
		if (collatRequired > unsignedAccountMarketValue) {
			isBelowMin = true;
			isAboveMax = false;
			collatToTransfer = collatRequired - unsignedAccountMarketValue;
		} else if (collatRequired < unsignedAccountMarketValue) {
			isBelowMin = false;
			isAboveMax = true;
			collatToTransfer = unsignedAccountMarketValue - collatRequired;
		}
	}
	//////////////////////////
	/// internal utilities ///
	//////////////////////////

	/** @notice function to change the perp position
        @param _amount the amount of position to open or close
        @return deltaChange The resulting difference in delta exposure
    */
	function _changePosition(int256 _amount) internal returns (int256) {
		if (syncOnChange) {
			sync();
		}
		uint256 collatToDeposit;
		uint256 collatToWithdraw;
		int256 positionOpened;
		// access the collateral held in the account
		(, uint256 collat) = clearingHouse.getAccountCollateralInfo(accountId, collateralId);
		// just make sure the collateral at index 0 is correct (this is unlikely to ever fail, but should be checked)
		if (collat == 0) {
			revert IncorrectCollateral();
		}
		// getAccountNetProfit and updateProfit
		// check the net position of the margin account
		int256 netPosition = clearingHouse.getAccountNetTokenPosition(accountId, poolId);
		// get the new net position with the amount of the swap added
		int256 newPosition = netPosition + _amount;
		// get the current price of the underlying asset from chainlink to be used to calculate position sizing
		uint256 currentPrice = OptionsCompute.convertToDecimals(
			PriceFeed(priceFeed).getNormalizedRate(wETH, collateralAsset),
			ERC20(collateralAsset).decimals()
		);
		// calculate the margin requirement for newPosition making sure to account for the health factor of the pool
		// as we want the position to be overcollateralised
		uint256 totalCollatNeeded = newPosition >= 0
			? (((uint256(newPosition) * currentPrice) / SCALE_UP) * healthFactor) / MAX_BIPS
			: (((uint256(-newPosition) * currentPrice) / SCALE_UP) * healthFactor) / MAX_BIPS;
		// if there is not enough collateral then increase the margin collateral balance
		// if there is too much collateral then decrease the margin collateral balance
		if (totalCollatNeeded > collat) {
			collatToDeposit = totalCollatNeeded - collat;
		} else if (totalCollatNeeded < collat) {
			collatToWithdraw = collat - Math.max(totalCollatNeeded, 1);
		} else if (totalCollatNeeded == collat && _amount != 0) {
			// highly improbable but if collateral is exactly equal if the amount to hedge is exactly opposite of the current
			// hedge then just swap without changing the margin
			// make the swapParams
			IClearingHouseStructures.SwapParams memory swapParams = IClearingHouseStructures.SwapParams(
				_amount,
				0,
				false,
				false,
				false
			);
			// execute the swap
			(positionOpened, ) = clearingHouse.swapToken(accountId, poolId, swapParams);
		} else {
			// this will happen if amount is 0
			return 0;
		}
		// if the current margin held is smaller than the new margin required then deposit more collateral
		// and open more positions
		// if the current margin held is larger than the new margin required then swap tokens out and
		// withdraw the excess margin
		if (collatToDeposit > 0) {
			if (ILiquidityPool(parentLiquidityPool).getBalance(LPcollateralAsset) < collatToDeposit) {
				revert CustomErrors.WithdrawExceedsLiquidity();
			}
			// transfer assets from the liquidityPool to here to collateralise the pool
			_transferIn(collatToDeposit);
			// deposit the collateral into the margin account
			clearingHouse.updateMargin(accountId, collateralId, int256(collatToDeposit));
			// make the swapParams
			IClearingHouseStructures.SwapParams memory swapParams = IClearingHouseStructures.SwapParams(
				_amount,
				0,
				false,
				false,
				false
			);
			// execute the swap
			(positionOpened, ) = clearingHouse.swapToken(accountId, poolId, swapParams);
		} else if (collatToWithdraw > 0) {
			// make the swapParams to close the position
			IClearingHouseStructures.SwapParams memory swapParams = IClearingHouseStructures.SwapParams(
				_amount,
				0,
				false,
				false,
				false
			);
			// execute the swap, since this is a withdrawal and we may withdraw all we want to make sure the account is properly settled
			// so we update the margin, if it fails then we settle any profits and update
			(positionOpened, ) = clearingHouse.swapToken(accountId, poolId, swapParams);
			try clearingHouse.updateMargin(accountId, collateralId, -int256(collatToWithdraw)) {} catch (
				bytes memory reason
			) {
				// way of catching custom errors referenced here: https://ethereum.stackexchange.com/questions/125238/catching-custom-error
				bytes4 expectedSelector = InvalidTransactionNotEnoughMargin.selector;
				bytes4 receivedSelector = bytes4(reason);
				assert(expectedSelector == receivedSelector);
				// settle the profits to make sure the collateral is covered
				clearingHouse.settleProfit(accountId);
				// get the new collat
				(, collat) = clearingHouse.getAccountCollateralInfo(accountId, collateralId);
				// if the collat value is smaller than collatToWithdraw then withdraw all collat
				if (collat <= collatToWithdraw && collat != 0) {
					collatToWithdraw = collat - 1;
				}
				clearingHouse.updateMargin(accountId, collateralId, -int256(collatToWithdraw));
			}
			// transfer assets back to the liquidityPool
			_transferOut(collatToWithdraw);
		}
		// make sure that _amount and positionOpened are the same, if they are not then revert
		if (positionOpened != _amount) { revert IncorrectDeltaChange();}
		return _amount;
	}

	function _transferIn(uint256 _amount) internal {
		uint256 _amountInMaximum = (_amount * 10050) / 10000;
		if (ILiquidityPool(parentLiquidityPool).getBalance(LPcollateralAsset) < _amountInMaximum) {
			revert CustomErrors.WithdrawExceedsLiquidity();
		}
		// transfer funds from the liquidity pool here
		SafeTransferLib.safeTransferFrom(LPcollateralAsset, parentLiquidityPool, address(this), _amountInMaximum);
		// convert from the native usdc to bridged usdc 
		ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
			tokenIn: LPcollateralAsset,
			tokenOut: collateralAsset,
			fee: 100,
			recipient: address(this),
			deadline: block.timestamp,
			amountOut: _amount,
			amountInMaximum: _amountInMaximum,
			sqrtPriceLimitX96: 0
		});
		// Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
		uint256 amountIn = swapRouter.exactOutputSingle(params);
		// transfer any remainder funds back to the liquidity pool
		SafeTransferLib.safeTransfer(
			ERC20(LPcollateralAsset),
			parentLiquidityPool,
			ERC20(LPcollateralAsset).balanceOf(address(this))
		);
	}

	function _transferOut(uint256 _amount) internal {
		uint256 _amountOutMinimum = (_amount * 9950) / 10000;
		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
			tokenIn: collateralAsset,
			tokenOut: LPcollateralAsset,
			fee: 100,
			recipient: parentLiquidityPool,
			deadline: block.timestamp,
			amountIn: _amount,
			amountOutMinimum: _amountOutMinimum,
			sqrtPriceLimitX96: 0
		});
		uint256 amountOut = swapRouter.exactInputSingle(params);
	}

	/// @dev keepers, managers or governors can access
	function _isKeeper() internal view {
		if (
			!keeper[msg.sender] &&
			msg.sender != authority.governor() &&
			msg.sender != authority.manager() &&
			msg.sender != parentLiquidityPool
		) {
			revert CustomErrors.NotKeeper();
		}
	}
}


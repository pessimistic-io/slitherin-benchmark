// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./PRBMathUD60x18.sol";
import "./PRBMathSD59x18.sol";

import "./PriceFeed.sol";

import "./AccessControl.sol";
import "./OptionsCompute.sol";
import "./SafeTransferLib.sol";

import "./ILiquidityPool.sol";
import "./IHedgingReactor.sol";
import "./IRouter.sol";
import "./IPositionRouter.sol";
import "./IReader.sol";
import "./IGmxVault.sol";
import "./Math.sol";

/**
 *  @title A hedging reactor that will manage delta by opening or closing short or long perp positions using GMX
 *  @dev interacts with LiquidityPool via hedgeDelta, getDelta, getPoolDenominatedValue and withdraw,
 *       interacts with GMX via _increasePosition and _decreasePosition
 */

contract GmxHedgingReactor is IHedgingReactor, AccessControl {
	using PRBMathSD59x18 for int256;
	using PRBMathUD60x18 for uint256;
	/////////////////////////////////
	/// immutable state variables ///
	/////////////////////////////////

	/// @notice address of the parent liquidity pool contract
	address public immutable parentLiquidityPool;
	/// @notice collateralAsset used for collateralising the pool
	address public immutable collateralAsset;
	/// @notice address of the wETH contract
	address public immutable wETH;
	/// @notice the gmx vault contract address
	IGmxVault public immutable vault;

	/////////////////////////
	/// dynamic variables ///
	/////////////////////////

	/// @notice delta of the pool
	int256 public internalDelta;
	bool public pendingIncreaseCallback;
	bool public pendingDecreaseCallback;
	mapping(bytes32 => int256) public increaseOrderDeltaChange;
	mapping(bytes32 => int256) public decreaseOrderDeltaChange;

	/////////////////////////////////////
	/// governance settable variables ///
	/////////////////////////////////////

	/// @notice address of the keeper of this pool
	mapping(address => bool) public keeper;
	/// @notice desired healthFactor of the pool
	uint256 public healthFactor = 5_000;
	/// @notice price deviation tolerance for collateral swapping
	uint256 public collateralSwapPriceTolerance = 5e15; // 0.5%
	/// @notice price tolerance for opening/closing positions
	uint256 public positionPriceTolerance = 5e15; // 0.5%
	/// @notice address of the price feed used for getting asset prices
	address public priceFeed;
	/// @notice the GMX position router contract
	IPositionRouter public gmxPositionRouter;
	/// @notice the GMX Router contract
	IRouter public router;
	/// @notice the GMX Reader contract
	IReader public reader;

	//////////////////////////
	/// constant variables ///
	//////////////////////////

	/// @notice used for unlimited token approval
	uint256 private constant MAX_UINT = 2**256 - 1;
	/// @notice max bips
	uint256 private constant MAX_BIPS = 10_000;

	//////////////
	/// events ///
	//////////////

	event CreateIncreasePosition(bytes32 positionKey);
	event CreateDecreasePosition(bytes32 positionKey);

	constructor(
		address _gmxPositionRouter,
		address _gmxRouter,
		address _gmxReader,
		address _gmxVault,
		address _collateralAsset,
		address _wethAddress,
		address _parentLiquidityPool,
		address _priceFeed,
		address _authority
	) AccessControl(IAuthority(_authority)) {
		router = IRouter(_gmxRouter);
		reader = IReader(_gmxReader);
		vault = IGmxVault(_gmxVault);
		gmxPositionRouter = IPositionRouter(_gmxPositionRouter);
		router.approvePlugin(_gmxPositionRouter);
		parentLiquidityPool = _parentLiquidityPool;
		wETH = _wethAddress;
		collateralAsset = _collateralAsset;
		priceFeed = _priceFeed;
	}

	receive() external payable {}

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

	function setPositionRouter(address _gmxPositionRouter) external {
		_onlyGovernor();
		router.denyPlugin(address(gmxPositionRouter));
		gmxPositionRouter = IPositionRouter(_gmxPositionRouter);
		router.approvePlugin(_gmxPositionRouter);
	}

	function setReader(address _reader) external {
		_onlyGovernor();
		reader = IReader(_reader);
	}

	function setRouter(address _router) external {
		_onlyGovernor();
		router = IRouter(_router);
	}

	function setPriceFeed(address _priceFeed) external {
		_onlyGovernor();
		priceFeed = _priceFeed;
	}

	function setCollateralSwapPriceTolerance(uint256 _collateralSwapPriceTolerance) external {
		_onlyGovernor();
		collateralSwapPriceTolerance = _collateralSwapPriceTolerance;
	}

	function setPositionPriceTolerance(uint256 _positionPriceTolerance) external {
		_onlyGovernor();
		positionPriceTolerance = _positionPriceTolerance;
	}

	////////////////////////////////////////////
	/// access-controlled external functions ///
	////////////////////////////////////////////

	function sweepFunds(uint256 _amount, address _receiver) external {
		_onlyGovernor();
		uint256 balance = address(this).balance;
		SafeTransferLib.safeTransferETH(_receiver, _amount > balance ? balance : _amount);
	}

	/// @inheritdoc IHedgingReactor
	function hedgeDelta(int256 _delta) external returns (int256 deltaChange) {
		require(_delta != 0, "delta change is zero");

		// delta is passed in as the delta that the pool has so this function must hedge the opposite
		// if delta comes in negative then the pool must go long
		// if delta comes in positive then the pool must go short
		// the signs must be flipped when going into _changePosition
		// make sure the caller is the vault
		require(msg.sender == parentLiquidityPool, "!vault");
		deltaChange = _changePosition(-_delta);
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
			SafeTransferLib.safeTransfer(ERC20(collateralAsset), msg.sender, _amount);
			// return in collateral format
			return _amount;
		} else {
			SafeTransferLib.safeTransfer(ERC20(collateralAsset), msg.sender, balance);
			// return in collateral format
			return balance;
		}
	}

	/// @notice function to re-calibrate internalDelta in case of liquidation
	function sync() external returns (int256) {
		_isKeeper();
		uint256[] memory longPosition = _getPosition(true);
		uint256[] memory shortPosition = _getPosition(false);
		uint256 longDelta = longPosition[0] > 0 ? (longPosition[0]).div(longPosition[2]) : 0;
		uint256 shortDelta = shortPosition[0] > 0 ? (shortPosition[0]).div(shortPosition[2]) : 0;
		internalDelta = int256(longDelta) - int256(shortDelta);
		return internalDelta;
	}

	/// @inheritdoc IHedgingReactor
	function update() external returns (uint256) {
		_isKeeper();
		if (internalDelta == 0) {
			revert CustomErrors.NoPositionsOpen();
		}

		(
			bool isBelowMin,
			bool isAboveMax,
			int256 health,
			uint256 collatToTransfer,
			uint256[] memory position
		) = checkVaultHealth();
		if (isBelowMin) {
			// collateral needs adding to position
			_addCollateral(collatToTransfer, internalDelta > 0);
			return collatToTransfer;
		} else if (isAboveMax) {
			// collateral needs removing
			// check if collateral removed would put position within 10% of liquidation limit
			// where positionSize / collateral is >= maxLeverage()
			if (
				// maxLeverage is multiplied by 10000 in contract. divide by 11000 to allow for 10% buffer.
				int256(position[1] / 1e24) - int256(collatToTransfer) < int256((position[0] / 1e24) / (vault.maxLeverage() / 11000))
			) {
				collatToTransfer = position[1] / 1e24 - (position[0] / 1e24) / (vault.maxLeverage() / 11000);
				if (collatToTransfer == 0) {
					return 0;
				}
			}
			_removeCollateral(collatToTransfer, internalDelta > 0);
			return collatToTransfer;
		}
	}

	/**
	 *	@notice internal function called by update() to add more collateral to the perp position
	 *	@param _collateralAmount amount of collateral tokens to add. Denominated in e6
	 *	@param _isLong whether the perp position is long or short
	 **/
	function _addCollateral(uint256 _collateralAmount, bool _isLong)
		internal
		returns (bytes32 positionKey, int256 deltaChange)
	{
		return _increasePosition(0, _collateralAmount, _isLong);
	}

	/**
	 *	@notice internal function called by update() to removing collateral from the perp position
	 *	@param _collateralAmount amount of collateral tokens to add. Denominated in e6
	 *	@param _isLong whether the perp position is long or short
	 **/
	function _removeCollateral(uint256 _collateralAmount, bool _isLong)
		internal
		returns (bytes32 positionKey, int256 deltaChange)
	{
		return _decreasePosition(0, _collateralAmount, _isLong);
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
		uint256[] memory position = _getPosition(internalDelta > 0);
		if (position[7] == 1) {
			value = (position[1] + position[8]) / 1e12;
		} else {
			value = (position[1] - position[8]) / 1e12;
		}
	}

	/** @notice function to check the health of the margin account
	 *  @return isBelowMin is the margin below the health factor
	 *  @return isAboveMax is the margin above the health factor
	 *  @return health     the health factor of the account currently
	 *  @return collatToTransfer the amount of collateral required to return the margin account back to the health factor. e6
	 */
	function checkVaultHealth()
		public
		view
		returns (
			bool isBelowMin,
			bool isAboveMax,
			int256 health,
			uint256 collatToTransfer,
			uint256[] memory position
		)
	{
		position = _getPosition(internalDelta > 0);
		// position[0] = position size in USD
		// position[1] = collateral amount in USD
		// position[2] = average entry price of position
		// position[3] = entry funding rate
		// position[4] = does position have *realised* profit
		// position[5] = realised PnL
		// position[6] = timestamp of last position increase
		// position[7] = is position in profit
		// position[8] = current unrealised Pnl
		// HF = (collatSize + unrealised pnl) / positionSize

		if (position[0] == 0) {
			//no positions open
			return (false, false, int256(healthFactor), 0, position);
		}
		int256 health;
		if (position[7] == 1) {
			//position in profit
			health = int256(((position[1] + position[8]).div(position[0]) * MAX_BIPS) / 1e18);
		} else {
			//position in loss
			health = ((int256(position[1]) - int256(position[8])).div(int256(position[0])) * int256(MAX_BIPS)) / 1e18;
		}
		if (health > int256(healthFactor)) {
			// position is over-collateralised
			isAboveMax = true;
			isBelowMin = false;
			// health must be > 0 so can cast to uint
			collatToTransfer = ((uint256(health) - healthFactor) * position[0]) / MAX_BIPS / 1e24;
		} else if (health < int256(healthFactor)) {
			// position undercollateralised
			// more collateral needs adding
			isBelowMin = true;
			isAboveMax = false;
			collatToTransfer = uint256(((int256(healthFactor) - health) * int256(position[0])) / int256(MAX_BIPS) / 1e24);
		} else {
			// health factor is perfect
			return (false, false, health, 0, position);
		}
		return (isBelowMin, isAboveMax, health, collatToTransfer, position);
	}

	//////////////////////////
	/// internal utilities ///
	//////////////////////////

	/** @notice function to handle logic of when to open and close positions
	 *	GMX handles shorts and longs separately, so we only want to have either a short OR a long open
	 *	at any one time to aavoid paying borrow fees both ways.
	 *	This function will close off any shorts before opening longs and vice versa.
	 *  @param _amount the amount of delta to change exposure by. e18
	 *  @return deltaChange The resulting difference in delta exposure
	 */
	function _changePosition(int256 _amount) internal returns (int256) {
		bool closedOppositeSideFirst = false;
		int256 closedPositionDeltaChange;
		if (_amount > 0) {
			// enter long position
			if (internalDelta < 0) {
				// close short position before opening long
				uint256 adjustedPositionSize = _adjustedReducePositionSize(uint256(_amount));
				uint256 collateralToRemove = _getCollateralSizeDeltaUsd(false, closedOppositeSideFirst, adjustedPositionSize);
				(bytes32 positionKey, int256 deltaChange) = _decreasePosition(adjustedPositionSize, collateralToRemove, false);
				// update deltaChange for callback function
				decreaseOrderDeltaChange[positionKey] += deltaChange;

				// remove the adjustedPositionSize from _amount to get remaining amount of delta to hedge to open shorts with
				_amount = _amount - int256(adjustedPositionSize);
				if (_amount == 0) return int256(adjustedPositionSize);
				closedPositionDeltaChange = deltaChange;
				closedOppositeSideFirst = true;
			}

			uint256 collateralToAdd = _getCollateralSizeDeltaUsd(true, closedOppositeSideFirst, uint256(_amount));
			(bytes32 positionKey, int256 deltaChange) = _increasePosition(uint256(_amount), collateralToAdd, true);
			// update deltaChange for callback function
			increaseOrderDeltaChange[positionKey] += deltaChange;
			return deltaChange + closedPositionDeltaChange;
		} else {
			// _amount is negative
			// enter a short position
			if (internalDelta > 0) {
				// close longs first
				uint256 adjustedPositionSize = _adjustedReducePositionSize(uint256(-_amount));
				uint256 collateralToRemove = _getCollateralSizeDeltaUsd(false, closedOppositeSideFirst, adjustedPositionSize);
				(bytes32 positionKey, int256 deltaChange) = _decreasePosition(adjustedPositionSize, collateralToRemove, true);
				// update deltaChange for callback function
				decreaseOrderDeltaChange[positionKey] += deltaChange;

				// remove the adjustedPositionSize from _amount to get remaining amount of delta to hedge to open shorts with
				_amount = _amount + int256(adjustedPositionSize); // _amount is negative so addition needed
				if (_amount == 0) return -int256(adjustedPositionSize);
				closedPositionDeltaChange = deltaChange;
				closedOppositeSideFirst = true;
			}
			// increase short position
			uint256 collateralToAdd = _getCollateralSizeDeltaUsd(true, closedOppositeSideFirst, uint256(-_amount));
			(bytes32 positionKey, int256 deltaChange) = _increasePosition(uint256(-_amount), collateralToAdd, false);
			// update deltaChange for callback function
			increaseOrderDeltaChange[positionKey] += deltaChange;
			return deltaChange + closedPositionDeltaChange;
		}
	}

	/**
	 *	@notice internal function to handle increasing position size on GMX
	 *	@param _size ETH denominated size to increase position by. e18
	 *	@param _collateralSize amount of collateral to add. denominated in collateralAsset decimals.
	 *	@param _isLong whether the position is a long or short
	 *	@return positionKey the unique key of the GMX position
	 *	@return deltaChange the resulting delta change from the position increase
	 */
	function _increasePosition(
		uint256 _size,
		uint256 _collateralSize,
		bool _isLong
	) internal returns (bytes32 positionKey, int256 deltaChange) {
		// check if funds are available in Liquidity pool
		if (ILiquidityPool(parentLiquidityPool).getBalance(collateralAsset) < _collateralSize) {
			revert CustomErrors.WithdrawExceedsLiquidity();
		}
		if (pendingIncreaseCallback) {
			revert CustomErrors.GmxCallbackPending();
		}
		uint256 currentPrice = getUnderlyingPrice(wETH, collateralAsset);

		// take that amount of collateral from the Liquidity Pool and approve to GMX
		SafeTransferLib.safeTransferFrom(collateralAsset, parentLiquidityPool, address(this), _collateralSize);
		SafeTransferLib.safeApprove(ERC20(collateralAsset), address(router), _collateralSize);

		bytes32 positionKey = gmxPositionRouter.createIncreasePosition{ value: gmxPositionRouter.minExecutionFee() }(
			_createPathIncreasePosition(_isLong),
			wETH,
			_collateralSize,
			(_collateralSize * 1e12).mul(1e18 - collateralSwapPriceTolerance).div(currentPrice),
			_size.mul(currentPrice) * 1e12,
			_isLong,
			_isLong
				? currentPrice.mul(1e18 + positionPriceTolerance) * 1e12
				: currentPrice.mul(1e18 - positionPriceTolerance) * 1e12,
			gmxPositionRouter.minExecutionFee(),
			"ryskiamo",
			address(this)
		);
		emit CreateIncreasePosition(positionKey);
		pendingIncreaseCallback = true;
		return (positionKey, _isLong ? int256(_size) : -int256(_size));
	}

	/**
	 *	@notice internal function to handle decreasing position size on GMX
	 *	@param _size ETH denominated size to decrease position by. e18
	 *	@param _collateralSize amount of collateral to remove. denominated in collateralAsset decimals.
	 *	@param _isLong whether the position is a long or short
	 *	@return positionKey the unique key of the GMX position
	 *	@return deltaChange the resulting delta change from the position decrease
	 */
	function _decreasePosition(
		uint256 _size,
		uint256 _collateralSize,
		bool _isLong
	) internal returns (bytes32 positionKey, int256 deltaChange) {
		if (pendingDecreaseCallback) {
			revert CustomErrors.GmxCallbackPending();
		}
		uint256[] memory position = _getPosition(_isLong);
		uint256 currentPrice = getUnderlyingPrice(wETH, collateralAsset);

		// calculate change in dollar value of position
		// equal to (_size / abs(internalDelta)) * positionSize
		// expressed in e30 decimals
		uint256 positionSizeDeltaUsd = _getPositionSizeDeltaUsd(_size, position[0]);
		bytes32 positionKey = gmxPositionRouter.createDecreasePosition{ value: gmxPositionRouter.minExecutionFee() }(
			_createPathDecreasePosition(_isLong),
			wETH,
			_collateralSize * 1e24,
			positionSizeDeltaUsd,
			_isLong,
			parentLiquidityPool,
			_isLong
				? currentPrice.mul(1e18 - positionPriceTolerance) * 1e12
				: currentPrice.mul(1e18 + positionPriceTolerance) * 1e12, // mul by 0.995 e12 for slippage
			0,
			gmxPositionRouter.minExecutionFee(),
			false,
			address(this)
		);
		emit CreateDecreasePosition(positionKey);
		pendingDecreaseCallback = true;
		return (positionKey, _isLong ? -int256(_size) : int256(_size));
	}

	/**
	 *	@notice gets current position details from GMX reader contract
	 *	@param _isLong if the position to get details for is a long position
	 *	@return position an array of figures describing the state of the position
	 */
	function _getPosition(bool _isLong) private view returns (uint256[] memory position) {
		address[] memory indexToken = new address[](1);

		indexToken[0] = wETH;
		address[] memory collateralToken = new address[](1);
		bool[] memory isLong = new bool[](1);
		if (!_isLong) {
			// get short pos
			collateralToken[0] = collateralAsset;
			isLong[0] = false;
		} else {
			// get long pos
			collateralToken[0] = wETH;
			isLong[0] = true;
		}
		position = reader.getPositions(address(vault), address(this), collateralToken, indexToken, isLong);
	}

	/**
	 *	@notice a function that floors a reduce position sizeDelta to only be as big as the open position itself
	 *	@param _size number of deltas to decrease position by
	 *	@return adjustedSize the floored number of deltas to decrease position by
	 */
	function _adjustedReducePositionSize(uint256 _size) private view returns (uint256 adjustedSize) {
		return uint256(internalDelta.abs()) > _size ? _size : uint256(internalDelta.abs());
	}

	/**
	 *	@param _isLong if the position to be changed is long
	 *	@return path the _path array formatted for the GMX contract call
	 */
	function _createPathIncreasePosition(bool _isLong) internal view returns (address[] memory path) {
		if (_isLong) {
			address[] memory path = new address[](2);
			path[0] = collateralAsset;
			path[1] = wETH;
			return path;
		} else {
			address[] memory path = new address[](1);
			path[0] = collateralAsset;
			return path;
		}
	}

	/**
	 *	@param _isLong if the position to be changed is long
	 *	@return path the _path array formatted for the GMX contract call
	 */
	function _createPathDecreasePosition(bool _isLong) internal view returns (address[] memory path) {
		if (_isLong) {
			address[] memory path = new address[](2);
			path[0] = wETH;
			path[1] = collateralAsset;
			return path;
		} else {
			address[] memory path = new address[](1);
			path[0] = collateralAsset;
			return path;
		}
	}

	/**
	 *	@param _isIncreasePosition if the position is to be increased (or decreased)
	 *	@param _closedOppositeSideFirst in the case of an increase, true if an opposite position has been closed in the same transaction
	 *	@param _amount amount of deltas to change position by. e18
	 *	@return amount of collateral to add (for increase) or remove (for decrease). denominated in e6
	 */
	function _getCollateralSizeDeltaUsd(
		bool _isIncreasePosition,
		bool _closedOppositeSideFirst,
		uint256 _amount
	) private view returns (uint256) {
		// calculate amount of collateral to add or remove denominated in USDC
		//  for increase positions this is equal to collateral needed for extra margin plus rebalancing collateral to bring health factor back to 5000
		if (_isIncreasePosition) {
			if (_closedOppositeSideFirst) {
				// this is a new position so no pnl to account for
				return
					OptionsCompute.convertToDecimals(
						(_amount.mul(getUnderlyingPrice(wETH, collateralAsset)) * healthFactor) / MAX_BIPS,
						ERC20(collateralAsset).decimals()
					);
			}
			(bool isBelowMin, bool isAboveMax, , uint256 collatToTransfer, ) = checkVaultHealth();
			// this is the collateral needed to increase position with no health factor rebalancing
			uint256 extraPositionCollateral = OptionsCompute.convertToDecimals(
				(_amount.mul(getUnderlyingPrice(wETH, collateralAsset)) * healthFactor) / MAX_BIPS,
				ERC20(collateralAsset).decimals()
			);
			uint256 totalCollateralToAdd;
			if (isAboveMax && collatToTransfer > extraPositionCollateral) {
				// in this case there is a net collateral withdrawal needed which cannot be done with increasePosition
				// so just dont add any more collateral and have it rebalance later
				totalCollateralToAdd = 0;
			} else {
				// otherwise add the two collateral requirement parts to obtain total collateral input
				if (isAboveMax) {
					// take away excess collateral
					totalCollateralToAdd = extraPositionCollateral - collatToTransfer;
				} else {
					// add extra needed collateral
					totalCollateralToAdd = extraPositionCollateral + collatToTransfer;
				}
			}
			uint256[] memory position = _getPosition(internalDelta > 0);
			// check if collateral removed would put position within 10% of liquidation limit
			// where positionSize / collateral is >= maxLeverage()
			// maxLeverage is multiplied by 10000 in contract. divide by 11000 to allow for 10% buffer.
			uint256 minAllowedCollateral = OptionsCompute.convertToDecimals(
				((position[0] / 1e12 + _amount.mul(getUnderlyingPrice(wETH, collateralAsset)))) / (vault.maxLeverage() / 11000),
				ERC20(collateralAsset).decimals()
			);
			if (
				OptionsCompute.convertToDecimals(position[1] / 1e12, ERC20(collateralAsset).decimals()) + totalCollateralToAdd <
				minAllowedCollateral
			) {
				// position[1] cannot be bigger than minAllowedCollateral here - no underflow
				totalCollateralToAdd =
					minAllowedCollateral -
					OptionsCompute.convertToDecimals(position[1] / 1e12, ERC20(collateralAsset).decimals());
			}
			return totalCollateralToAdd;
		} else {
			uint256 leverageFactor = MAX_BIPS.div(healthFactor);
			// when decreasing a position, a proportion of the pnl (positive or negative) equal to the proportion of the
			// position size being reduced is taken out of the position.
			uint256[] memory position = _getPosition(internalDelta > 0);
			// position[0] = position size in USD
			// position[1] = collateral amount in USD
			// position[2] = average entry price of position
			// position[3] = entry funding rate
			// position[4] = does position have *realised* profit
			// position[5] = realised PnL
			// position[6] = timestamp of last position increase
			// position[7] = is position in profit
			// position[8] = current unrealised Pnl

			int256 collateralToRemove;
			if (position[7] == 1) {
				// position in profit
				// with positions in profit, you receive collateral out equal to the value entered for _collateralDelta in the createDecreasePosition
				// function PLUS the proportion of the pnl equal to proportion of position size being reduced.
				{
					collateralToRemove = (1e18 -
						(
							(int256(position[0] / 1e12) - int256((leverageFactor.mul(position[8])) / 1e12))
								.mul(1e18 - int256(_amount.mul(position[2]).div(position[0])))
								.div(int256(leverageFactor.mul(position[1]) / 1e12))
						)).mul(int256(position[1] / 1e12));
				}
			} else {
				// position in loss
				// with positions in loss, what is entered into the createDecreasePosition function is what you receive
				// however the pnl is still reduced proportionally
				uint256 d = _amount.mul(position[2]).div(position[0]);
				{
					collateralToRemove =
						(int256(position[1] / 1e12) - ((int256(position[0]) / 1e12).mul(1e18 - int256(d)).div(int256(leverageFactor)))) -
						int256(position[8] / 1e12);
				}
			}
			uint256 adjustedCollateralToRemove;
			// collateral to remove must be a uint
			if (collateralToRemove < 0) {
				adjustedCollateralToRemove = uint256(0);
			} else {
				adjustedCollateralToRemove = uint256(collateralToRemove);

				// check if collateral removed would put position within 10% of liquidation limit
				// where positionSize / collateral is >= maxLeverage()
				uint256 minAllowedCollateral = ((position[0] - _getPositionSizeDeltaUsd(_amount, position[0])) / 1e12) /
					(vault.maxLeverage() / 11000);
				if (
					// maxLeverage is multiplied by 10000 in contract. divide by 11000 to allow for 10% buffer.
					int256(position[1] / 1e12) - int256(adjustedCollateralToRemove) < int256(minAllowedCollateral)
				) {
					adjustedCollateralToRemove = position[1] / 1e12 - minAllowedCollateral;
					if (adjustedCollateralToRemove == 0) {
						return 0;
					}
				}
			}
			return OptionsCompute.convertToDecimals(adjustedCollateralToRemove, ERC20(collateralAsset).decimals());
		}
	}

	/**	@notice GMX position size remains fixed through price fluctuations and is denominated in USD.
							This function converts from ETH denominated delta to USD denominated position size change
	 *	@param _size amount of deltas to change position by. e18
	 *	@param positionSize USD size of existing position as given by GMX. e30
	 *	@return USD size to change position by. e30
	 */
	function _getPositionSizeDeltaUsd(uint256 _size, uint256 positionSize) private view returns (uint256) {
		return _size.mul(positionSize).div(uint256(internalDelta.abs()));
	}

	// ---- functions to force execution in case of GMX keeper failure
	function executeIncreasePosition(bytes32 positionKey) external {
		gmxPositionRouter.executeIncreasePosition(positionKey, payable(address(this)));
	}

	function executeDecreasePosition(bytes32 positionKey) external {
		gmxPositionRouter.executeDecreasePosition(positionKey, payable(address(this)));
	}

	/**	@notice function which will be called by a GMX keeper when they execute or reject our position request
	 *	@param positionKey unique key of the position request given by GMX
	 *	@param isExecuted if the position change was executed successfully
	 *	@param isIncrease if the position was increased
	 */
	function gmxPositionCallback(
		bytes32 positionKey,
		bool isExecuted,
		bool isIncrease
	) external {
		if (msg.sender != address(gmxPositionRouter)) {
			revert CustomErrors.InvalidGmxCallback();
		}
		if (isExecuted) {
			if (isIncrease) {
				internalDelta += increaseOrderDeltaChange[positionKey];
			} else {
				internalDelta += decreaseOrderDeltaChange[positionKey];
			}
		}
		if (isIncrease) {
			pendingIncreaseCallback = false;
			delete increaseOrderDeltaChange[positionKey];
		} else {
			pendingDecreaseCallback = false;
			delete decreaseOrderDeltaChange[positionKey];
		}
	}

	/**
	 * @notice get the underlying price with just the underlying asset and strike asset
	 * @param underlying   the asset that is used as the reference asset
	 * @param _strikeAsset the asset that the underlying value is denominated in
	 * @return the underlying price
	 */
	function getUnderlyingPrice(address underlying, address _strikeAsset) internal view returns (uint256) {
		return PriceFeed(priceFeed).getNormalizedRate(underlying, _strikeAsset);
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


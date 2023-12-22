// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

// Base
import "./ERC20Snapshot.sol";

// Utils
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Manageable.sol";

// Let's trigger the libs
import "./SafeERC20.sol";
import "./Math.sol";

// Interfaces
import "./IBridgeConnectorHome.sol";
import "./ISwapV2.sol";

/// @title Crate token
/** @notice This contract is an ERC4626 cross-chain vault that allows users to deposit assets
 *  and mint Crate tokens. The Crate tokens can be used to redeem the assets on the same chain.
 *  The funds deposited on the contract are themselves deposited on other protocols to generate yield.
 *  The revenue generated reflects on the token's share price, which represents the assets value per
 *  crate token.
 *
 *
 *  Withdraws are done locally, using an internal stableswap liquidity pool. When a user wants to
 *  redeem their tokens, a swap happens between the "virtual" asset in the pool and the actual asset,
 *  which is then sent to the user. This creates a buffer to process withdraws, without having to manage
 *  risky cross-chain interactions. If the pool is depleted, some negative slippage can appear for
 *  redeemers, but the contract will still be able to process withdraws and depositors will be rewarded
 *  for providing liquidity.
 *
 *
 *  The assets in the pool are rebalanced periodically, to ensure that the pool is always balanced. When
 *  this happens, the vault earns the positive slippage. Also, pool assets are not idle and are used to
 *  generate yield on other protocols, such as Aave.
 *  @dev Deposit/withdraw/Redeem functions can be overloaded to allow for slippage control.
 **/
contract Crate is Pausable, ReentrancyGuard, Manageable, ERC20Snapshot {
	using SafeERC20 for IERC20;

	struct ChainData {
		uint256 debt;
		uint256 maxDeposit;
		address bridge;
	}

	struct Checkpoint {
		uint256 timestamp;
		uint256 sharePrice;
	}

	struct ElasticLiquidityPool {
		uint256 debt; // How much vAssets are accounted in the pool
		uint256 liquidity; // How much assets do we have when the pool is balanced
		ISwap swap; // Where is the pool
	}
	/*//////////////////////////////////////////////////////////////
                                 ERRORS
  //////////////////////////////////////////////////////////////*/

	error AmountTooHigh(uint256 maxAmount);
	error AmountZero();
	error CrateCantBeReceiver();
	error IncorrectShareAmount(uint256 shares);
	error IncorrectAssetAmount(uint256 assets);
	error ZeroAddress();
	error ChainError();
	error FeeError();
	error Unauthorized();
	error LiquidityPoolNotSet();
	error TransactionExpired();
	error NoFundsToRebalance();
	error MinAmountTooLow(uint256 minAmount);
	error IncorrectArrayLengths();
	error InsufficientFunds(uint256 availableFunds);

	/*//////////////////////////////////////////////////////////////
                                // SECTION EVENTS
  //////////////////////////////////////////////////////////////*/

	event Deposit(
		address indexed sender, // Who sent the USDC
		address indexed owner, // who received the crate tokens
		uint256 assets, // ex: amount of USDC sent
		uint256 shares // amount of crate tokens minted
	);
	event Withdraw(
		address indexed sender,
		address indexed receiver,
		address indexed owner,
		uint256 assets,
		uint256 shares
	);
	event ChainDebtUpdated(
		uint256 newChainDebt,
		uint256 oldChainDebt,
		uint256 chainId
	);
	event SharePriceUpdated(uint256 shareprice, uint256 timestamp);
	event TakeFees(
		uint256 gain,
		uint256 totalAssets,
		uint256 managementFee,
		uint256 performanceFee,
		uint256 sharesMinted,
		address indexed receiver
	);
	event NewFees(uint256 performance, uint256 management, uint256 withdraw);
	event LiquidityRebalanced(uint256 recovered, uint256 earned);
	event PoolMigrated(address indexed newPool, uint256 seedAmount);
	event LiquidityChanged(uint256 oldLiquidity, uint256 newLiquidity);
	event LiquidityPoolEnabled(bool enabled);
	event MigrationFailed();
	event ChainAdded(uint256 chainId, address bridge);
	event MaxDepositForChainSet(uint256 chainId, uint256 maxDeposit);
	event MaxTotalAssetsSet(uint256 maxTotalAssets);

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                        // SECTION VARIABLES
  //////////////////////////////////////////////////////////////*/
	uint256 public maxTotalAssets; // Max amount of assets in the vault
	uint256 public totalRemoteAssets; // Amount of assets on other chains (or farmed on local chain)
	uint256 public performanceFee; // 100% = 10000
	uint256 public managementFee; // 100% = 10000
	uint256 public withdrawFee; // 100% = 10000
	uint256 public anticipatedProfits; // The yield trickling down
	uint256 public lastUpdate; // Last time the unrealized gain was updated
	uint256[] public chainList; // List of chains that can be used

	// This allows us to do some bookeeping
	mapping(uint256 => ChainData) public chainData; // Chain data

	Checkpoint public checkpoint; // Used to compute fees
	ElasticLiquidityPool public liquidityPool; // The pool used to process withdraws

	uint8 private tokenDecimals; // The decimals of the token
	bool public liquidityPoolEnabled; // If the pool is enabled

	mapping(address => bool) public bridgeWhitelist; // BridgeConnectors that can be used

	IERC20 public asset; // The asset we are using

	uint256 private constant MAX_BPS = 10000; // 100%
	uint256 private constant MAX_PERF_FEE = 10000; // 100%
	uint256 private constant MAX_MGMT_FEE = 500; // 5%
	uint256 private constant MAX_WITHDRAW_FEE = 200; // 2%
	uint256 private constant MAX_UINT256 = type(uint256).max;
	uint256 private constant COOLDOWN = 2 days; // The cooldown period for realizating gains
	uint256 private constant MIN_AMOUNT_RATIO = 970; // 97% of the amount

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                            // SECTION CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/
	constructor(
		address _asset, // The asset we are using
		string memory _name, // The name of the token
		string memory _symbol, // The symbol of the token
		uint256 _performanceFee, // 100% = 10000
		uint256 _managementFee, // 100% = 10000
		uint256 _withdrawFee // 100% = 10000
	) ERC20(_name, _symbol) {
		if (_performanceFee > MAX_PERF_FEE) revert FeeError();
		if (_managementFee > MAX_MGMT_FEE) revert FeeError();
		if (_withdrawFee > MAX_WITHDRAW_FEE) revert FeeError();

		asset = IERC20(_asset);
		performanceFee = _performanceFee;
		managementFee = _managementFee;
		withdrawFee = _withdrawFee;
		tokenDecimals = IERC20Metadata(_asset).decimals();
		checkpoint = Checkpoint(block.timestamp, 10 ** tokenDecimals);
		_pause(); // We start paused
	}

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                        // SECTION MODIFIERS
  //////////////////////////////////////////////////////////////*/
	/// @notice Checks if the sender is the bridge
	modifier onlyBridgeConnector() {
		if (bridgeWhitelist[msg.sender] == false) revert Unauthorized();
		_;
	}

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                        // SECTION DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
	/// @dev If the liquidity pool is imbalanced, the user will get some positive slippage from replenishing it.
	/// @param _amount The amount of underlying tokens to deposit
	/// @param _receiver The address that will get the tokens
	//  @param _minShareAmount Minimum amount of shares to be minted, like slippage on Uniswap
	//  @param _deadline Transaction should revert if exectued after this deadline
	/// @return shares the amount of tokens minted to the _receiver
	function safeDeposit(
		uint256 _amount,
		address _receiver,
		uint256 _minShareAmount,
		uint256 _deadline
	) external returns (uint256 shares) {
		return _deposit(_amount, _receiver, _minShareAmount, _deadline);
	}

	/// @notice Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
	/// @dev If the liquidity pool is imbalanced, the user will get some positive slippage from replenishing it.
	/// @dev This version is here for ERC4626 compatibility and doesn't have slippage and deadline control
	/// @param _amount The amount of underlying tokens to deposit
	/// @param _receiver The address that will get the tokens
	/// @return shares the amount of tokens minted to the _receiver
	function deposit(
		uint256 _amount,
		address _receiver
	) external returns (uint256 shares) {
		return _deposit(_amount, _receiver, 0, block.timestamp);
	}

	/// @dev Pausing the contract should prevent depositing by setting maxDepositAmount
	/// to 0
	function _deposit(
		uint256 _amount,
		address _receiver,
		uint256 _minShareAmount,
		uint256 _deadline
	) internal nonReentrant returns (uint256 shares) {
		// Requires

		if (_receiver == address(this)) revert CrateCantBeReceiver();
		if (_amount == 0) revert AmountZero();
		if (_amount > maxDeposit(address(0)))
			revert AmountTooHigh(maxDeposit(_receiver));
		// We save totalAssets before transfering
		uint256 assetsAvailable = totalAssets();

		// Moving value
		asset.safeTransferFrom(msg.sender, address(this), _amount);
		// If we have a liquidity pool, we use it
		if (liquidityPoolEnabled) {
			ElasticLiquidityPool memory pool = liquidityPool;

			// If the pool is unbalanced, we get the amount to swap to rebalance it
			uint256 toSwap = _getAmountToSwap(_amount, pool);
			if (toSwap > 0) {
				uint256 swapped = pool.swap.swapAssetToVirtual(
					toSwap,
					_deadline
				);
				liquidityPool.debt += swapped;
				// We credit the bonus
				_amount = _amount + swapped - toSwap;
			}
		} else if (block.timestamp > _deadline) {
			revert TransactionExpired();
		} // We can now compute the amount of shares we'll mint
		uint256 supply = totalSupply();
		shares = supply == 0
			? _amount
			: Math.mulDiv(_amount, supply, assetsAvailable);

		if (shares == 0 || shares < _minShareAmount) {
			revert IncorrectShareAmount(shares);
		}

		// We mint crTokens
		_mint(_receiver, shares);
		emit Deposit(msg.sender, _receiver, _amount, shares);
	}

	/// @notice Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
	/// @dev Bear in mind that this function doesn't interact with the liquidity pool, so you may be
	/// missing some positive slippage if the pool is imbalanced.
	/// @param _shares the amount of tokens minted to the _receiver
	/// @param _receiver The address that will get the tokens
	/// @return assets The The amount of underlying tokens deposited
	function mint(
		uint256 _shares,
		address _receiver
	) external nonReentrant returns (uint256 assets) {
		assets = convertToAssets(_shares);

		// Requires
		if (assets == 0 || _shares == 0) revert AmountZero();
		if (assets > maxDeposit(_receiver))
			revert AmountTooHigh(maxDeposit(_receiver));
		if (_receiver == address(this)) revert CrateCantBeReceiver();

		// Moving value
		asset.safeTransferFrom(msg.sender, address(this), assets);
		_mint(_receiver, _shares);
		emit Deposit(msg.sender, _receiver, assets, _shares);
	}

	/// @notice Order a withdraw from the liquidity pool
	/// @dev Beware, there's no slippage control - you need to use the overloaded function if you want it
	/// @param _amount Amount of funds to pull (ex: 1000 USDC)
	/// @param _receiver Who will get the withdrawn assets
	/// @param _owner Whose crTokens we'll burn
	function withdraw(
		uint256 _amount,
		address _receiver,
		address _owner
	) external returns (uint256 shares) {
		// This represents the amount of crTokens that we're about to burn
		shares = previewWithdraw(_amount); // We take fees here
		_withdraw(_amount, shares, 0, block.timestamp, _receiver, _owner);
	}

	/// @notice Order a withdraw from the liquidity pool
	/// @dev Overloaded version with slippage control
	/// @param _amount Amount of funds to pull (ex: 1000 USDC)
	/// @param _receiver Who will get the withdrawn assets
	/// @param _owner Whose crTokens we'll burn
	function safeWithdraw(
		uint256 _amount,
		uint256 _minAmount,
		uint256 _deadline,
		address _receiver,
		address _owner
	) external returns (uint256 shares) {
		// This represents the amount of crTokens that we're about to burn
		shares = previewWithdraw(_amount); // We take fees here
		_withdraw(_amount, shares, _minAmount, _deadline, _receiver, _owner);
	}

	/// @notice Redeem crTokens for their underlying value
	/// @dev We do this to respect the ERC46626 interface
	/// Beware, there's no slippage control - you need to use the overloaded function if you want it
	/// @param _shares The amount of crTokens to redeem
	/// @param _receiver Who will get the withdrawn assets
	/// @param _owner Whose crTokens we'll burn
	function redeem(
		uint256 _shares,
		address _receiver,
		address _owner
	) external returns (uint256 assets) {
		return (
			_withdraw(
				(convertToAssets(_shares) * (MAX_BPS - withdrawFee)) / MAX_BPS, // We take fees here
				_shares,
				0,
				block.timestamp,
				_receiver,
				_owner
			)
		);
	}

	/// @notice Redeem crTokens for their underlying value
	/// @dev Overloaded version with slippage control
	/// @param _shares The amount of crTokens to redeem
	/// @param _minAmountOut The minimum amount of assets we'll accept
	/// @param _receiver Who will get the withdrawn assets
	/// @param _owner Whose crTokens we'll burn
	/// @return assets Amount of assets recovered
	function safeRedeem(
		uint256 _shares,
		uint256 _minAmountOut, // Min_amount
		uint256 _deadline,
		address _receiver,
		address _owner
	) external returns (uint256 assets) {
		return (
			_withdraw(
				(convertToAssets(_shares) * (MAX_BPS - withdrawFee)) / MAX_BPS, // We take fees here
				_shares, // _shares
				_minAmountOut,
				_deadline,
				_receiver, // _receiver
				_owner // _owner
			)
		);
	}

	/// @notice The vault takes a small fee to prevent share price updates arbitrages
	/// @dev Logic used to pull tokens from the router and process accounting
	/// @dev Fees should already have been taken into account
	function _withdraw(
		uint256 _amount,
		uint256 _shares,
		uint256 _minAmountOut,
		uint256 _deadline,
		address _receiver,
		address _owner
	) internal nonReentrant whenNotPaused returns (uint256 recovered) {
		if (_amount == 0 || _shares == 0) revert AmountZero();

		// We spend the allowance if the msg.sender isn't the receiver
		if (msg.sender != _owner) {
			_spendAllowance(_owner, msg.sender, _shares);
		}

		// Check for rounding error since we round down in previewRedeem.
		if (convertToAssets(_shares) == 0)
			revert IncorrectAssetAmount(convertToAssets(_shares));

		// We burn the tokens
		_burn(_owner, _shares);

		uint256 assetBal = asset.balanceOf(address(this));

		// If there are enough funds in the vault, we just send them
		if (assetBal > 0 && assetBal >= _amount) {
			recovered = _amount;
			asset.safeTransfer(_receiver, recovered);
			// If there aren't enough funds in the vault, we need to pull from the liquidity pool
		} else if (liquidityPoolEnabled) {
			// We first send the funds that we have
			if (assetBal > 0) {
				recovered = assetBal;
				asset.safeTransfer(_receiver, recovered);
			}

			uint256 toRecover = _amount - recovered;
			recovered += liquidityPool.swap.swapVirtualToAsset(
				toRecover,
				0, // Check is done after
				_deadline,
				_receiver
			);

			// We don't take into account the eventual slippage, since it will
			// be paid to the depositoors
			liquidityPool.debt -= Math.min(toRecover, liquidityPool.debt);
		} else {
			revert InsufficientFunds(assetBal);
		}

		if (_minAmountOut > 0 && recovered < _minAmountOut)
			revert IncorrectAssetAmount(recovered);

		emit Withdraw(msg.sender, _receiver, _owner, _amount, _shares);
	}

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                        // SECTION LIQUIDITY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

	// TODO: Should this function be whitelisted?
	/// @notice Rebalance the Liquidity pool using idle funds and liquid strats
	function rebalanceLiquidityPool()
		public
		whenNotPaused
		returns (uint256 earned)
	{
		// Reverts if we the LP is not enabled
		if (!liquidityPoolEnabled) revert LiquidityPoolNotSet();

		// We check if we have enough funds to rebalance
		uint256 toSwap = _getAmountToSwap(
			asset.balanceOf(address(this)),
			liquidityPool
		);

		if (toSwap == 0) revert NoFundsToRebalance();
		uint256 recovered = liquidityPool.swap.swapAssetToVirtual(
			toSwap,
			block.timestamp + 100
		);
		liquidityPool.debt += recovered;
		earned = recovered - Math.min(toSwap, recovered);

		emit LiquidityRebalanced(recovered, earned);
		emit SharePriceUpdated(sharePrice(), block.timestamp);
	}

	/// @notice Order a deposit to the different chains, which will move funds accordingly
	/// @dev Another call at the router level is needed to send the funds
	/// @param _amounts The amount to process. This allows to let a buffer for withdraws, if needed
	/// @param _minAmounts The minimum amount to accept for each chain
	/// @param _chainIds self-explanatory
	/// @param _msgValues value to send the call to the bridge, if needed
	/// @param _bridgeData data to send the call to the bridge, if needed
	function dispatchAssets(
		uint256[] calldata _amounts,
		uint256[] calldata _minAmounts,
		uint256[] calldata _chainIds,
		uint256[] calldata _msgValues,
		bytes[] calldata _bridgeData
	) external payable onlyKeeper {
		if (
			_amounts.length != _minAmounts.length ||
			_amounts.length != _chainIds.length ||
			_amounts.length != _msgValues.length ||
			_amounts.length != _bridgeData.length
		) revert IncorrectArrayLengths();

		for (uint256 i = 0; i < _amounts.length; i++) {
			ChainData memory data = chainData[_chainIds[i]];
			// checks
			if (_minAmounts[i] < (_amounts[i] * MIN_AMOUNT_RATIO) / 1000)
				revert MinAmountTooLow((_amounts[i] * MIN_AMOUNT_RATIO) / 1000); // prevents setting minAmount too low
			if (data.maxDeposit == 0) revert ChainError(); // Chain not active
			if (data.maxDeposit <= data.debt + _amounts[i])
				revert AmountTooHigh(data.maxDeposit); // No more funds can be sent to this chain

			chainData[_chainIds[i]].debt += _amounts[i];
			totalRemoteAssets += _amounts[i];
			asset.safeTransfer(data.bridge, _amounts[i]);
			if (block.chainid != _chainIds[i]) {
				IBridgeConnectorHome(data.bridge).bridgeFunds{
					value: _msgValues[i]
				}(_amounts[i], _chainIds[i], _minAmounts[i], _bridgeData[i]);
			}
		}
	}

	/// @notice Migrate from one liquidity pool to another
	/// @dev This allows you to earn the full positive slippage, if some is missing
	/// @dev Disable the liquidity pool by migrating it to address(0)
	/// @param _newPool Address of the new pool
	/// @param _seedAmount Amount of liquidity to add to the new pool
	function migrateLiquidityPool(
		address _newPool,
		uint256 _seedAmount
	) external onlyAdmin {
		ISwap swap = liquidityPool.swap;
		// If we already have a pool, we withdraw our funds from it
		if (address(swap) != address(0)) {
			try swap.migrate() {} catch {
				emit MigrationFailed();
			}
			// We remove the allowance
			asset.safeDecreaseAllowance(
				address(swap),
				asset.allowance(address(this), address(swap))
			);
		}

		// We set the new pool or disable the liquidity pool
		if (_newPool == address(0)) {
			liquidityPoolEnabled = false;
			liquidityPool.swap = ISwap(address(0));
			liquidityPool.debt = 0;
			liquidityPool.liquidity = 0;
			emit PoolMigrated(_newPool, 0);
			emit LiquidityPoolEnabled(false);
			return;
		}

		// Approving
		// https://github.com/code-423n4/2021-10-slingshot-findings/issues/81
		asset.safeIncreaseAllowance(address(_newPool), 0);
		asset.safeIncreaseAllowance(address(_newPool), MAX_UINT256);

		// We need to register the new liquidity
		liquidityPool.swap = ISwap(_newPool);

		// We can now add liquidity to it
		if (_seedAmount > 0) {
			ISwap(_newPool).addLiquidity(_seedAmount, block.timestamp + 100);
			liquidityPoolEnabled = true;
			liquidityPool.debt = _seedAmount;
			liquidityPool.liquidity = _seedAmount;
		} else {
			liquidityPoolEnabled = false;
		}

		emit PoolMigrated(_newPool, _seedAmount);
		emit LiquidityPoolEnabled(liquidityPoolEnabled);
	}

	/// @notice Increase the amount of liquidity in the pool
	/// @dev We must have enough idle liquidity to do it
	/// If that's not the case, pull liquid funds first
	/// @param _liquidityAdded Amount of liquidity to add to the pool
	function increaseLiquidity(uint256 _liquidityAdded) external onlyKeeper {
		uint256 oldLiquidity = liquidityPool.liquidity;
		liquidityPool.liquidity = oldLiquidity + _liquidityAdded;
		liquidityPool.debt += _liquidityAdded;

		// We add equal amounts of tokens
		// To avoid any slippage, rebalance first
		// Given that the pool floors calculations, it's not possible to rebalance 1:1
		// hence why we don't have a hard require on the pool being balanced
		liquidityPool.swap.addLiquidity(_liquidityAdded, block.timestamp);

		emit LiquidityChanged(oldLiquidity, oldLiquidity + _liquidityAdded);
	}

	/// @notice Decrease the amount of liquidity in the pool
	/// @param _liquidityRemoved Amount of liquidity to add to the pool
	function decreaseLiquidity(uint256 _liquidityRemoved) external onlyKeeper {
		// Rebalance first the pool to avoid any negative slippage
		uint256 lpBal = liquidityPool.swap.getVirtualLpBalance();
		uint256 assetBalBefore = asset.balanceOf(address(this));
		uint256 liquidityBefore = liquidityPool.liquidity;

		// we remove liquidity
		liquidityPool.liquidity -= _liquidityRemoved;
		// We specify the amount of LP that corresponds to the amount of liquidity removed
		liquidityPool.swap.removeLiquidity(
			(lpBal * _liquidityRemoved) / liquidityBefore,
			block.timestamp
		);
		// We update the book
		liquidityPool.debt -= (asset.balanceOf(address(this)) - assetBalBefore);
		emit LiquidityChanged(
			liquidityBefore,
			liquidityBefore - _liquidityRemoved
		);
	}

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                // SECTION ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Linearization of the accrued gains
	/// @dev This is used to calculate the total assets under management
	/// @return The amount of gains that are not yet realized
	function unrealizedGains() public view returns (uint256) {
		return
			// Death by ternary
			lastUpdate + COOLDOWN < block.timestamp // If cooldown is over
				? 0 // all gains are realized
				: anticipatedProfits - // Otherwise, we calculate the gains
					((1e6 *
						(anticipatedProfits * (block.timestamp - lastUpdate))) /
						COOLDOWN) /
					1e6; // We scale by 1e6 to avoid rounding errors with low decimals
	}

	/// @notice Amount of assets under management
	/// @dev We consider each chain/pool as having "debt" to the crate
	/// @return The total amount of assets under management
	function totalAssets() public view returns (uint256) {
		return
			(asset.balanceOf(address(this)) +
				totalRemoteAssets +
				liquidityPool.debt) - unrealizedGains();
	}

	/// @notice Decimals of the crate token
	/// @return The number of decimals of the crate token
	function decimals() public view override returns (uint8) {
		return (tokenDecimals);
	}

	/// @notice The share price equal the amount of assets redeemable for one crate token
	/// @return The virtual price of the crate token
	function sharePrice() public view returns (uint256) {
		uint256 supply = totalSupply();

		return
			supply == 0
				? 10 ** decimals()
				: Math.mulDiv(totalAssets(), 10 ** decimals(), supply);
	}

	/// @notice Convert how much crate tokens you can get for your assets
	/// @param _assets Amount of assets to convert
	/// @return The amount of crate tokens you can get for your assets
	function convertToShares(uint256 _assets) public view returns (uint256) {
		uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
		// shares = assets * supply / totalDebt
		return
			supply == 0 ? _assets : Math.mulDiv(_assets, supply, totalAssets());
	}

	/// @notice Convert how much asset tokens you can get for your crate tokens
	/// @dev Bear in mind that some negative slippage may happen
	/// @param _shares amount of shares to covert
	/// @return The amount of asset tokens you can get for your crate tokens
	function convertToAssets(uint256 _shares) public view returns (uint256) {
		uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
		return
			supply == 0 ? _shares : Math.mulDiv(_shares, totalAssets(), supply);
	}

	function _getAmountToSwap(
		uint256 _assets,
		ElasticLiquidityPool memory pool
	) internal view returns (uint256 toSwap) {
		uint256 poolImbalance = pool.liquidity -
			Math.min(pool.swap.getAssetBalance(), pool.liquidity);

		// If there's an imbalance, we replenish the pool
		if (poolImbalance > 0) {
			return (Math.min(poolImbalance, _assets));
		}
	}

	/// @notice Convert how much crate tokens you can get for your assets
	/// @param _assets Amount of assets that we deposit
	/// @return shares Amount of share tokens that the user should receive
	function previewDeposit(
		uint256 _assets
	) external view returns (uint256 shares) {
		if (liquidityPoolEnabled) {
			ElasticLiquidityPool memory pool = liquidityPool;
			uint256 toSwap = _getAmountToSwap(_assets, pool);

			// If there's an imbalance, we replenish the pool
			if (toSwap > 0) {
				uint256 swapped = pool.swap.calculateAssetToVirtual(toSwap);
				// We credit the bonus
				_assets = _assets - toSwap + swapped;
			}
		}

		return convertToShares(_assets);
	}

	/// @notice Preview how much asset tokens the user has to pay to acquire x shares
	/// @param _shares Amount of shares that we acquire
	/// @return shares Amount of asset tokens that the user should pay
	function previewMint(uint256 _shares) public view returns (uint256) {
		return convertToAssets(_shares);
	}

	/// @notice Preview how much shares the user needs to burn to get asset tokens
	/// @dev You may get less asset tokens than you expect due to slippage
	/// @param _assets How much we want to get
	/// @return How many shares we need to burn
	function previewWithdraw(uint256 _assets) public view returns (uint256) {
		return convertToShares((_assets * MAX_BPS) / (MAX_BPS - withdrawFee));
	}

	/// @notice Preview how many asset tokens the user will get for x shares
	/// @param shares Amount of shares that we burn
	/// @return Amount of asset tokens that the user will get for x shares
	function previewRedeem(uint256 shares) public view returns (uint256) {
		uint256 vAssets = convertToAssets(shares);
		vAssets -= (vAssets * withdrawFee) / MAX_BPS;

		uint256 recovered = asset.balanceOf(address(this));
		if (liquidityPoolEnabled && recovered < vAssets) {
			return
				recovered +
				liquidityPool.swap.calculateVirtualToAsset(vAssets - recovered);
		}

		return asset.balanceOf(address(this)) >= vAssets ? vAssets : 0;
	}

	// @notice acknowledge the sending of funds and update debt book
	/// @param _chainId Id of the chain that sent the funds
	/// @param _amount Amount of funds sent
	function receiveBridgedFunds(
		uint256 _chainId,
		uint256 _amount
	) external onlyBridgeConnector {
		asset.safeTransferFrom(msg.sender, address(this), _amount);
		uint256 oldDebt = chainData[_chainId].debt;
		chainData[_chainId].debt -= Math.min(oldDebt, _amount);
		totalRemoteAssets -= Math.min(totalRemoteAssets, _amount);

		emit ChainDebtUpdated(chainData[_chainId].debt, oldDebt, _chainId);
		emit SharePriceUpdated(sharePrice(), block.timestamp);
	}

	/// @notice Update the debt book
	/// @param _chainId Id of the chain that had a debt update
	/// @param _newDebt New debt of the chain
	function updateChainDebt(
		uint256 _chainId,
		uint256 _newDebt
	) external onlyBridgeConnector {
		uint256 oldDebt = chainData[_chainId].debt;

		chainData[_chainId].debt = _newDebt;
		uint256 debtDiff = _newDebt - Math.min(_newDebt, oldDebt);
		if (debtDiff > 0) {
			// We update the anticipated profits
			anticipatedProfits = debtDiff + unrealizedGains();
			lastUpdate = block.timestamp;
		}

		totalRemoteAssets = totalRemoteAssets + _newDebt - oldDebt;

		emit ChainDebtUpdated(_newDebt, oldDebt, _chainId);
		emit SharePriceUpdated(sharePrice(), block.timestamp);
	}

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                     // SECTION DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice The maximum amount of assets that can be deposited
	/// @return The maximum amount of assets that can be deposited
	function maxDeposit(address) public view returns (uint256) {
		uint256 maxAUM = maxTotalAssets;
		return maxAUM - Math.min(totalAssets(), maxAUM);
	}

	/// @notice The maximum amount of shares that can be minted
	/// @return The maximum amount of shares that can be minted
	function maxMint(address) public view returns (uint256) {
		return convertToShares(maxDeposit(address(0)));
	}

	/// @notice The maximum amount of assets that can be withdrawn
	/// @return The maximum amount of assets that can be withdrawn
	function maxWithdraw(address _owner) external view returns (uint256) {
		return paused() ? 0 : convertToAssets(balanceOf(_owner));
	}

	/// @notice The maximum amount of shares that can be redeemed
	/// @return The maximum amount of shares that can be redeemed
	function maxRedeem(address _owner) external view returns (uint256) {
		return paused() ? 0 : balanceOf(_owner);
	}

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                              // SECTION FEES
    //////////////////////////////////////////////////////////////*/

	/// @notice Take fees from the vault
	/// @dev This function is called by the owner of the vault
	function takeFees() external onlyAdmin {
		(
			uint256 performanceFeeAmount,
			uint256 managementFeeAmount,
			uint256 gain
		) = computeFees();

		if (gain == 0) return;

		uint256 sharesMinted = convertToShares(
			performanceFeeAmount + managementFeeAmount
		);

		_mint(msg.sender, sharesMinted);
		checkpoint = Checkpoint(block.timestamp, sharePrice());

		emit TakeFees(
			gain,
			totalAssets(),
			managementFeeAmount,
			performanceFeeAmount,
			sharesMinted,
			msg.sender
		);
	}

	/// @notice Compute the fees that should be taken
	///  @dev The fees are computed based on the last checkpoint
	/// @dev Fees are computed in terms of % of the vault, then scaled to the total assets
	/// @return performanceFeeAmount The amount of performance fee
	/// @return managementFeeAmount The amount of management fee
	/// @return gain The gain of the vault since last checkpoint
	function computeFees()
		public
		view
		returns (
			uint256 performanceFeeAmount,
			uint256 managementFeeAmount,
			uint256 gain
		)
	{
		// We get the elapsed time since last time
		Checkpoint memory lastCheckpoint = checkpoint;
		uint256 duration = block.timestamp - lastCheckpoint.timestamp;
		if (duration == 0) return (0, 0, 0); // Can't call twice per block

		uint256 currentSharePrice = sharePrice();
		gain =
			Math.max(lastCheckpoint.sharePrice, currentSharePrice) -
			lastCheckpoint.sharePrice;

		if (gain == 0) return (0, 0, 0); // If the contract hasn't made any gains, we do not take fees

		uint256 currentTotalAssets = totalAssets();

		// We compute the fees relative to the sharePrice
		// For instance, if the management fee is 1%, and the sharePrice is 200,
		// the "relative" management fee is 2 after a year
		uint256 managementFeeRelative = (currentSharePrice *
			managementFee *
			duration) /
			MAX_BPS /
			365 days;

		// Same with performance fee
		uint256 performanceFeeRelative = (gain * performanceFee) / MAX_BPS;

		// This allows us to check if the gain is enough to cover the fees
		if (managementFeeRelative + performanceFeeRelative > gain) {
			managementFeeRelative = gain - performanceFeeRelative;
		}

		// We can now compute the fees in terms of assets
		performanceFeeAmount =
			(performanceFeeRelative * currentTotalAssets) /
			currentSharePrice;

		managementFeeAmount =
			(managementFeeRelative * currentTotalAssets) /
			currentSharePrice;

		return (performanceFeeAmount, managementFeeAmount, gain);
	}

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                            // SECTION SETTERS
    //////////////////////////////////////////////////////////////*/

	/// @notice Add a new chain to the vault or update one
	/// @param _chainId Id of the chain to add
	/// @param _maxDeposit Max amount of assets that can be deposited on that chain
	/// @param _bridgeAddress Address of the bridge connector
	/// @param _allocator Address of the remote allocator
	/// @param _remoteConnector Address of the remote connector
	/// @param _params Parameters to pass to the bridge connector
	function addChain(
		uint256 _chainId,
		uint256 _maxDeposit,
		address _bridgeAddress,
		address _allocator,
		address _remoteConnector,
		bytes calldata _params
	) external onlyAdmin {
		// if it's the local chain we don't need to setup a bridge
		if (block.chainid != _chainId)
			IBridgeConnectorHome(_bridgeAddress).addChain(
				_chainId,
				_allocator,
				_remoteConnector,
				_params
			);

		// IF the chain has not been added yet, we add it to the list
		if (chainData[_chainId].bridge == address(0)) chainList.push(_chainId);
		chainData[_chainId].maxDeposit = _maxDeposit;
		chainData[_chainId].bridge = _bridgeAddress;
		bridgeWhitelist[_bridgeAddress] = true;
		emit ChainAdded(_chainId, _bridgeAddress);
	}

	function enableLiquidityPool(
		bool _liquidityPoolEnabled
	) external onlyManager {
		liquidityPoolEnabled = _liquidityPoolEnabled;
		if (address(liquidityPool.swap) == address(0))
			revert LiquidityPoolNotSet();
		emit LiquidityPoolEnabled(liquidityPoolEnabled);
	}

	/// @notice Set the max deposit for a chain
	/// @param _maxDeposit Max amount of assets that can be deposited on that chain
	/// @param _chainId Id of the chain
	function setMaxDepositForChain(
		uint256 _maxDeposit,
		uint256 _chainId
	) external onlyManager {
		if (chainData[_chainId].bridge == address(0)) revert ChainError();
		chainData[_chainId].maxDeposit = _maxDeposit;
		emit MaxDepositForChainSet(_maxDeposit, _chainId);
	}

	/// @notice Set the max amount of total assets that can be deposited
	/// @dev There can be more assets than this, however if that's the case then
	/// no deposits are allowed
	/// @param _amount max amount of assets
	function setMaxTotalAssets(uint256 _amount) external onlyManager {
		// We need to unpause first the vault if it's paused
		// This prevents the vault to accept deposits but not withdraws
		if (maxTotalAssets == 0 && paused()) {
			revert();
		}
		// We seed the vault with some assets if it's empty
		maxTotalAssets = _amount;
		uint256 seedDeposit = 10 ** 8;
		if (totalSupply() == 0)
			_deposit(seedDeposit, msg.sender, seedDeposit, block.timestamp);
		emit MaxTotalAssetsSet(_amount);
	}

	/// @notice Set the fees
	/// @dev Maximum fees are registered as constants
	/// @param _performanceFee Fee on performance
	/// @param _managementFee Annual fee
	/// @param _withdrawFee Fee on withdraw, mainly to avoid MEV/arbs
	function setFees(
		uint256 _performanceFee,
		uint256 _managementFee,
		uint256 _withdrawFee
	) external onlyAdmin {
		// Safeguards
		if (
			_performanceFee > MAX_PERF_FEE ||
			_managementFee > MAX_MGMT_FEE ||
			_withdrawFee > MAX_WITHDRAW_FEE
		) revert FeeError(); // Fees are too high

		performanceFee = _performanceFee;
		managementFee = _managementFee;
		withdrawFee = _withdrawFee;
		emit NewFees(performanceFee, managementFee, withdrawFee);
	}

	// !SECTION

	/*//////////////////////////////////////////////////////////////
                            // SECTION UTILS
    //////////////////////////////////////////////////////////////*/

	receive() external payable {}

	/// @notice Pause the crate
	function pause() external onlyManager {
		_pause();
		// This prevents deposit
		maxTotalAssets = 0;
	}

	/// @notice Unpause the crate
	/// @dev We seed the crate with 1e8 tokens if it's empty
	function unpause() external onlyManager {
		_unpause();
	}

	/// @notice Take a snapshot of the crate balances
	function snapshot() external onlyManager returns (uint256 id) {
		id = _snapshot();
		emit Snapshot(id);
	}

	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 amount
	) internal override(ERC20Snapshot) {
		super._beforeTokenTransfer(from, to, amount);
	}

	/// @notice Rescue any ERC20 token that is stuck in the contract
	function rescueToken(address _token, bool _onlyETH) external onlyAdmin {
		// We send any trapped ETH
		payable(msg.sender).transfer(address(this).balance);

		if (_onlyETH) return;

		if (_token == address(asset)) revert();
		IERC20 tokenToRescue = IERC20(_token);
		tokenToRescue.transfer(
			msg.sender,
			tokenToRescue.balanceOf(address(this))
		);
	}

	/// @notice Estimate the cost of a deposit on a chain
	/// @param _chainIds Ids of the chains
	/// @param _amounts Amounts to deposit
	/// @return nativeCost Cost of the deposit in native token
	function estimateDispatchCost(
		uint256[] calldata _chainIds,
		uint256[] calldata _amounts
	) external view returns (uint256[] memory) {
		if (_amounts.length != _chainIds.length) {
			revert IncorrectArrayLengths();
		}
		uint256 length = _chainIds.length;
		uint256[] memory nativeCost = new uint256[](length);
		for (uint256 i; i < length; i++) {
			if (_chainIds[i] == block.chainid) continue;
			nativeCost[i] = IBridgeConnectorHome(chainData[_chainIds[i]].bridge)
				.estimateBridgeCost(_chainIds[i], _amounts[i]);
		}
		return (nativeCost);
	}
}


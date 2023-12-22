// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma abicoder v2;
// ERC support
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";

// Math
import { Math } from "./Math.sol";
import { SafeMath } from "./SafeMath.sol";

// Uniswap
import { IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { TickMath } from "./TickMath.sol";
import { SqrtPriceMath } from "./SqrtPriceMath.sol";
import { FullMath } from "./FullMath.sol";
import { IUniswapV3MintCallback } from "./IUniswapV3MintCallback.sol";
import { IUniswapV3SwapCallback } from "./IUniswapV3SwapCallback.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { PositionKey } from "./PositionKey.sol";

// Util support
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { AccessControlUpgradeable } from "./AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { StringsUpgradeable } from "./StringsUpgradeable.sol";

// Sundry
import { IBareVaultRegistry } from "./IBareVaultRegistry.sol";
import { IBaseDeposit } from "./IBaseDeposit.sol";

abstract contract BaseLiquidityManager is
    Initializable,
    ERC20Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Storage

    uint256 internal constant PRECISION = 1e18;

    /// @dev Can collect Steer fees
    bytes32 internal constant STEER_ROLE = keccak256("STEER_ROLE");
    /// @dev Can call tend function
    bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Fee info
    /// @dev Fee rates, each multiplied by 10,000
    ///      (a TOTAL_FEE of 100 means a 1% cut of total uniswap fees)
    /// @dev Total fraction of fees not going towards LPs, multiplied by 10,000
    uint256 public constant TOTAL_FEE = 15_00;
    /// @dev Total fraction of fees going towards Steer (as opposed to going towards strategist)
    uint256 public constant STEER_FRACTION_OF_FEE = 66_67;
    uint256 internal constant FEE_DIVISOR = 100_00;
    uint256 internal constant ONE_MINUS_FEE = FEE_DIVISOR - TOTAL_FEE;

    /// @dev Address of Uniswap Factory
    IUniswapV3Factory internal constant FACTORY =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    /// @dev Address of vault registry
    ///      Address strategist can collect strategist fees, but is not stored here.
    address internal vaultRegistry;

    /// @notice Addresses of Token0 and Token1
    IERC20 public token0;
    IERC20 public token1;

    /// @dev Fees currently owed to Steer
    uint256 public accruedSteerFees0;
    uint256 public accruedSteerFees1;

    /// @dev Fees currently owed to strategist
    uint256 public accruedStrategistFees0;
    uint256 public accruedStrategistFees1;

    /// @notice Address of Uniswap V3 pool
    IUniswapV3Pool public pool;

    /// @dev For depositing
    ///      Roughly corresponds to a 5% diff between current price and twap price
    int24 public maxTickChange;

    /// @dev Number of seconds to get the time-weighted average over
    uint32 public twapInterval;

    // Modifiers

    modifier onlyRole(bytes32 _role) {
        require(hasRole(_role, msg.sender), "R");
        _;
    }

    // Events

    /// @dev Pool/vault info as of the end of a tend
    /// @param sqrtPriceX96 Current pool price
    /// @param totalAmount0 The total user-owned token0, including funds held in the vault
    ///                     and funds deposited into the pool
    /// @param totalSupply The total number of shares in this vault.
    event Snapshot(
        uint160 sqrtPriceX96,
        uint256 totalAmount0,
        uint256 totalAmount1,
        uint256 totalSupply
    );

    /// @dev Deposit info
    /// @param sender The address which provided the tokens
    /// @param to The receiver of vault shares from this deposit, generally the same as sender
    /// @param shares The number of shares that have been minted by this deposit
    /// @param amount0 The amount of t0 that was used to mint the shares
    /// @param amount1 The amount of t1 that was used to mint the shares
    event Deposit(
        address indexed sender,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    /// @dev Withdraw info
    /// @param sender msg.sender and the owner of the shares being burned
    /// @param to The receiver of the tokens earned via the burn
    /// @param shares The number of shares being burned
    /// @param amount0 The amount of t0 earned via the burn
    /// @param amount1 The amount of t1 earned via the burn
    event Withdraw(
        address indexed sender,
        address indexed to,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    /// @dev Info on protocol fees earned. Triggers whenever a withdraw or a tend happens.
    /// @param amount0Earned Total t0 fees earned, including fees going to steer and strategist.
    /// @param amount1Earned Total t1 fees earned, including fees going to steer and strategist.
    event FeesEarned(uint256 amount0Earned, uint256 amount1Earned);

    // Constructor

    constructor() initializer {}

    // External Functions

    /// @notice Withdraws tokens in proportion to the vault's holdings.
    /// @param shares Shares burned by sender
    /// @param amount0Min Revert if resulting `amount0` is smaller than this
    /// @param amount1Min Revert if resulting `amount1` is smaller than this
    /// @param to Recipient of tokens
    /// @return amount0 Amount of token0 sent to recipient
    /// @return amount1 Amount of token1 sent to recipient
    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external virtual returns (uint256 amount0, uint256 amount1) {
        // Shares to withdraw must be greater than zero
        require(shares > 0);

        uint256 _totalSupply = totalSupply();

        // Burn LPTs
        _burn(msg.sender, shares);

        // Calculate token amounts proportional to unused balances
        // LP value = (Value deposited in Uniswap + value held in vault undeposited) / total LP tokens.
        // Here we calculate value held in vault undeposited.
        // No div(0) safemath here because totalSupply != 0;
        // since shares != 0 and totalSupply >= shares
        amount0 = FullMath.mulDiv(_getBalance0(), shares, _totalSupply);
        amount1 = FullMath.mulDiv(_getBalance1(), shares, _totalSupply);

        // Withdraw proportion of liquidity from Uniswap pool
        (uint256 t0FromPool, uint256 t1FromPool) = _burnAndCollect(
            shares,
            _totalSupply
        );

        // In addition to their share of vault-held tokens,
        // withdraw their share of uniswap-held tokens.
        amount0 = amount0.add(t0FromPool);
        amount1 = amount1.add(t1FromPool);

        require(amount0 >= amount0Min);
        require(amount1 >= amount1Min);

        // Push tokens to recipient
        _transferTokens(to, amount0, amount1);

        emit Withdraw(msg.sender, to, shares, amount0, amount1);
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata /* data */
    ) external override {
        require(msg.sender == address(pool));

        _transferTokens(msg.sender, amount0, amount1);
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3SwapCallback(
        int256 amount0Wanted,
        int256 amount1Wanted,
        bytes calldata /* data */
    ) external override {
        require(msg.sender == address(pool));

        if (amount0Wanted > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Wanted));
        }
        if (amount1Wanted > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Wanted));
        }
    }

    /// @notice Used to collect accumulated protocol fees.
    function steerCollectFees(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external onlyRole(STEER_ROLE) whenNotPaused {
        (accruedSteerFees0, accruedSteerFees1) = _collectFees(
            to,
            accruedSteerFees0,
            accruedSteerFees1,
            amount0,
            amount1
        );
    }

    /// @notice Used to collect accumulated protocol fees.
    function strategistCollectFees(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external whenNotPaused {
        // Make sure msg.sender is NFT holder of this vault
        require(
            msg.sender ==
                IBareVaultRegistry(vaultRegistry).getStrategyCreatorForVault(
                    address(this)
                )
        );

        (accruedStrategistFees0, accruedStrategistFees1) = _collectFees(
            to,
            accruedStrategistFees0,
            accruedStrategistFees1,
            amount0,
            amount1
        );
    }

    /// @notice Removes liquidity in case of emergency.
    function emergencyBurn(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        external
        onlyRole(STEER_ROLE)
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = pool.burn(tickLower, tickUpper, liquidity);
        pool.collect(
            address(this),
            tickLower,
            tickUpper,
            type(uint128).max,
            type(uint128).max
        );
    }

    /// @notice Used by periphery to verify vault is depositable.
    function supportsInterface(
        bytes4 interfaceId
    ) external view returns (bool) {
        return
            IBareVaultRegistry(vaultRegistry).doISupportInterface(interfaceId);
    }

    /// @dev Pause and unpause
    function pause() external onlyRole(STEER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(STEER_ROLE) {
        _unpause();
    }

    // Public Functions

    /// @dev Initializes vault
    /// @param _vaultManager is the address which will manage the vault being created, pass orchestrator address if the vault is meant to be managed by the orchestrator
    /// @param _steer The steer multisig address, responsible for some governance functions.
    /// @param _params All other parameters this vault will use
    function initialize(
        address _vaultManager,
        address, //orchestrator not needed here as, if this vault is to be managed by orchestrator, _vaultManager parameter should be the orchestrator address
        address _steer,
        bytes memory _params
    ) public virtual initializer {
        // _token0 is address of token0
        // _token1 is address of token1
        // _poolFee is Uniswap pool fee, how much is charged for a swap
        // _maxTickChange is max difference between TWAP tick and current tick,
        //      useful for protection against frontrunning. Cannot be negative.
        // _twapInterval is the number of seconds to get the time-weighted average over
        (
            address _token0,
            address _token1,
            uint24 _poolFee,
            int24 _maxTickChange,
            uint32 _twapInterval
        ) = abi.decode(_params, (address, address, uint24, int24, uint32));

        // Validate input parameters
        require(_maxTickChange > 9 && _maxTickChange < 2001);
        require(_twapInterval > 5 && _twapInterval < 600);
        require(_token0 < _token1, "T");

        // Context inits
        vaultRegistry = msg.sender;
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        // Get relevant pool from uniswap factory
        address _pool = FACTORY.getPool(_token0, _token1, _poolFee);

        // Revert if pool doesn't exist yet
        require(_pool != address(0));

        // Set pool
        pool = IUniswapV3Pool(_pool);

        // Init the LP token ERC20 using totalVaultCount from the vaultRegistry
        // Naming system: STEER_VAULT_$TotalVaultCount, i.e. STEER_VAULT_20
        string memory vaultCount = StringsUpgradeable.toString(
            IBareVaultRegistry(msg.sender).totalVaultCount() + 1
        );
        __ERC20_init(
            string(abi.encodePacked("STEER_UNIV3_VAULT_", vaultCount)),
            string(abi.encodePacked("STEER_UNIV3_VAULT_", vaultCount))
        );

        // Init everything else
        __Pausable_init();
        __AccessControl_init();

        _setupRole(STEER_ROLE, _steer);
        _setupRole(MANAGER_ROLE, _vaultManager);

        // Set security params
        maxTickChange = _maxTickChange;
        twapInterval = _twapInterval;
    }

    /// @notice Deposits tokens in proportion to the vault's current holdings.
    /// @dev These tokens sit in the vault and are not used for liquidity on
    ///      Uniswap until the next rebalance.
    ///      function requirements:
    ///        Either amount0Desired or amount1Desired must be > 0 or it will revert with 'CROSS'
    /// @param amount0Desired Max amount of token0 to deposit
    /// @param amount1Desired Max amount of token1 to deposit
    /// @param amount0Min Revert if resulting amount0Used is less than this
    /// @param amount1Min Revert if resulting amount1Used is less than this
    /// @param to Recipient of shares
    /// @return shares Number of shares minted
    /// @return amount0Used Amount of token0 deposited
    /// @return amount1Used Amount of token1 deposited
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    )
        public
        virtual
        whenNotPaused
        returns (uint256 shares, uint256 amount0Used, uint256 amount1Used)
    {
        IBareVaultRegistry.VaultState state = IBareVaultRegistry(vaultRegistry)
            .getVaultDetails(address(this))
            .state;
        require(
            state == IBareVaultRegistry.VaultState.PendingThreshold ||
                state == IBareVaultRegistry.VaultState.Active,
            "Invalid Vault State"
        );
        // Update pool fees earned
        poke();

        // Calculate amounts proportional to vault's holdings
        (shares, amount0Used, amount1Used) = _calcSharesAndAmounts(
            amount0Desired,
            amount1Desired
        );

        // Make sure deposit meets slippage requirements.
        // If amount0Used < amount0Min or amount1Used < amount1Min,
        // there has been too much slippage.
        require(shares > 0);
        require(amount0Used >= amount0Min, "0");
        require(amount1Used >= amount1Min, "1");

        // Pull in tokens from sender
        if (amount0Used > 0) {
            token0.safeTransferFrom(msg.sender, address(this), amount0Used);
        }
        if (amount1Used > 0) {
            token1.safeTransferFrom(msg.sender, address(this), amount1Used);
        }

        // Mint shares to recipient
        _mint(to, shares);
        emit Deposit(msg.sender, to, shares, amount0Used, amount1Used);
    }

    function poke() public virtual;

    function getTotalAmounts() public view virtual returns (uint256, uint256);

    // Internal Functions

    /// @dev Wrapper around `IUniswapV3Pool.positions()`.
    /// @param tickLower Lower bound of position whose info is requested
    /// @param tickUpper Upper bound of position
    /// @return liquidity The amount of liquidity owned by this position
    /// @return feeGrowthInside0LastX128 Fee growth per unit of liquidity
    ///           as of the last update to liquidity or fees owed
    /// @return feeGrowthInside1LastX128 Fee growth per unit of liquidity
    ///           as of the last update to liquidity or fees owed
    /// @return tokensOwed0 The fees owed to the position owner in token0
    /// @return tokensOwed1 The fees owed to the position owner in token1
    function _position(
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint128, uint256, uint256, uint128, uint128) {
        return
            pool.positions(
                PositionKey.compute(address(this), tickLower, tickUpper)
            );
    }

    /// @dev Calculates the largest possible `amount0` and `amount1` such that
    ///      they're in the same proportion as total amounts, but not greater than
    ///      `amount0Desired` and `amount1Desired` respectively.
    function _calcSharesAndAmounts(
        uint256 amount0Desired,
        uint256 amount1Desired
    )
        internal
        view
        returns (uint256 shares, uint256 amount0Used, uint256 amount1Used)
    {
        uint256 _totalSupply = totalSupply();
        (uint256 total0, uint256 total1) = getTotalAmounts();

        // If total supply > 0, vault can't be empty.
        assert(_totalSupply == 0 || total0 > 0 || total1 > 0);

        if (_totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0Used = amount0Desired;
            amount1Used = amount1Desired;
            shares = Math.max(amount0Used, amount1Used);
        } else if (total0 == 0) {
            shares = FullMath.mulDiv(amount1Desired, _totalSupply, total1);
            amount1Used = FullMath.mulDivRoundingUp(
                shares,
                total1,
                _totalSupply
            );
        } else if (total1 == 0) {
            shares = FullMath.mulDiv(amount0Desired, _totalSupply, total0);
            amount0Used = FullMath.mulDivRoundingUp(
                shares,
                total0,
                _totalSupply
            );
        } else {
            uint256 cross = Math.min(
                amount0Desired.mul(total1),
                amount1Desired.mul(total0)
            );

            // If cross is zero, this means that the inputted ratio is totally wrong
            // and must be adjusted to better match the vault's held ratio.
            // This pretty much only happens if all of the vault's holdings are in one token,
            // and the user wants to exclusively deposit the other token.
            require(cross > 0, "C");

            // Round up amounts
            // cross - 1 can be unchecked since above we require cross != 0
            // total1 and total0 are also both > 0
            amount0Used = ((cross - 1) / total1) + 1;
            amount1Used = ((cross - 1) / total0) + 1;

            shares = FullMath.mulDiv(cross, _totalSupply, total0) / total1;
        }
    }

    function _transferTokens(
        address to,
        uint256 amount0,
        uint256 amount1
    ) internal {
        if (amount0 > 0) {
            token0.safeTransfer(to, amount0);
        }
        if (amount1 > 0) {
            token1.safeTransfer(to, amount1);
        }
    }

    /// @dev Withdraws liquidity from all positions, allocating fees correctly in the process.
    /// @param shares LP shares being withdrawn
    /// @param totalShares Total # of LP tokens in the vault
    /// @return t0 Token0 earned from burned liquidity + fees.
    ///            Only includes burned + fees corresponding to LP shares being withdrawn (100% if tend)
    /// @return t1 Token1 earned from burned liquidity + fees
    function _burnAndCollect(
        uint256 shares,
        uint256 totalShares
    ) internal virtual returns (uint256 t0, uint256 t1);

    /// @dev revert if volatility is above acceptable levels
    ///      (mainly used to prevent flashloan attacks)
    /// @param currentTick Current pool tick
    function _checkVolatility(int24 currentTick) internal view {
        // SLOADS for efficiency
        uint32 _twapInterval = twapInterval;
        int24 _maxTickChange = maxTickChange;

        // Get TWAP tick
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = _twapInterval; // From 45 seconds ago

        // tickCumulatives is basically where the tick was as of twapInterval seconds ago
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

        // tickCumulatives[1] will always be greater than [0]
        // so no need to check for underflow or division overflow here.
        int24 twapTick = int24(
            (tickCumulatives[1] - tickCumulatives[0]) / _twapInterval
        );

        // Make sure currentTick is not more than maxTickChange ticks away from twapTick
        // No SafeMath here--even if a compromised governance contract set _maxTickChange to a very high value,
        // it would only wrap around and cause this check to fail.
        require(
            currentTick <= twapTick + _maxTickChange &&
                currentTick >= twapTick - _maxTickChange,
            "V"
        );
    }

    /// @notice Balance of token0 in vault not used in any position.
    function _getBalance0() internal view returns (uint256) {
        return
            token0.balanceOf(address(this)).sub(
                accruedSteerFees0 + accruedStrategistFees0
            );
    }

    /// @notice Balance of token1 in vault not used in any position.
    function _getBalance1() internal view returns (uint256) {
        return
            token1.balanceOf(address(this)).sub(
                accruedSteerFees1 + accruedStrategistFees1
            );
    }

    /// @notice Amounts of token0 and token1 held in this position of the vault.
    ///         Includes owed fees.
    ///         Also includes fees paid to the protocol, so not everything returned here is owned by LPs.
    ///         Doesn't include fees accrued since last poke
    ///         (so includes all fees if poke was called as part of this transaction)
    function _getPositionAmounts(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper
    )
        internal
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 fees0,
            uint256 fees1
        )
    {
        uint128 liquidity;
        (liquidity, , , fees0, fees1) = _position(tickLower, tickUpper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
    }

    function _collectFees(
        address to,
        uint256 currentFee0,
        uint256 currentFee1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 fee0, uint256 fee1) {
        if (amount0 > 0) {
            fee0 = currentFee0.sub(amount0);
            token0.safeTransfer(to, amount0);
        } else {
            fee0 = currentFee0;
        }
        if (amount1 > 0) {
            fee1 = currentFee1.sub(amount1);
            token1.safeTransfer(to, amount1);
        } else {
            fee1 = currentFee1;
        }
    }

    // Gap

    /// @dev Useful if we upgrade to a contract which needs more storage slots
    /// This contract consumes 10 slots and following openzeppelin standards(50 - slots consumed by this contract i.e.50 - 10 = 40) the gap array size is set to 40
    uint256[40] private gap;
}


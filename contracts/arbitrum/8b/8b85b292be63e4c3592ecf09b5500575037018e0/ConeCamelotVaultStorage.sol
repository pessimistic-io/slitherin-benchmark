// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.4;

import {OwnableUninitialized} from "./OwnableUninitialized.sol";
import {IAlgebraPool} from "./IAlgebraPool.sol";
import {IERC20} from "./IERC20.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {LiquidityAmounts} from "./uniswap_LiquidityAmounts.sol";
import {TickMath} from "./uniswap_TickMath.sol";
import {SafeCast} from "./SafeCast.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {ConeCamelotLibrary} from "./ConeCamelotLibrary.sol";

/// @dev Single Global upgradeable state var storage base: APPEND ONLY
/// @dev Add all inherited contracts with state vars here: APPEND ONLY
/// @dev ERC20Upgradable Includes Initialize
// solhint-disable-next-line max-states-count
abstract contract ConeCamelotVaultStorage is
    ERC20Upgradeable /* XXXX DONT MODIFY ORDERING XXXX */,
    ReentrancyGuardUpgradeable,
    OwnableUninitialized
{
    // APPEND ADDITIONAL BASE WITH STATE VARS BELOW:
    // XXXX DONT MODIFY ORDERING XXXX

    // solhint-disable-next-line const-name-snakecase
    string public constant version = "1.0.0";
    /// @dev "restricted mint enabled" toggle value must be a number
    uint16 public constant RESTRICTED_MINT_ENABLED = 11111;

    address public immutable coneTreasury;

    // XXXXXXXX DO NOT MODIFY ORDERING XXXXXXXX


    uint16 public restrictedMintToggle;

    uint16 public coneFeeBPS;
    uint16 public managerFeeBPS;
    address public managerTreasury;

    uint256 public managerBalance0;
    uint256 public managerBalance1;
    uint256 public coneBalance0;
    uint256 public coneBalance1;

    IAlgebraPool public pool;
    IERC20 public token0;
    IERC20 public token1;
    // APPPEND ADDITIONAL STATE VARS BELOW:
    // XXXXXXXX DO NOT MODIFY ORDERING XXXXXXXX

    uint128 minLiquidityToMint;

    mapping(RangeType => int24) public lowerTicks;
    mapping(RangeType => int24) public upperTicks;

    mapping(RangeType => uint256) public percentageBIPS;

    mapping(RangeType => uint256) public liquidityInRange;
    mapping(RangeType => uint256) public tokensForRange;

    enum RangeType {
        Near,
        Medium,
        Far
    }

    event UpdateManagerParams(
        uint16 coneFeeBPS,
        uint16 managerFeeBPS,
        address managerTreasury
    );

    event FeesEarned(uint256 feesEarned0, uint256 feesEarned1);

    event Rebalance(int24 lowerTick_, int24 upperTick_, uint128 liquidityBefore, uint128 liquidityAfter);

    event EmergencyWithdraw();
    event CollectedFees(uint256 fee0, uint256 fee1);
    error Invalid_Percentage_BIPS();

    using TickMath for int24;
    using SafeERC20 for IERC20;

    // solhint-disable-next-line max-line-length
    constructor(address _coneTreasury) {
        coneTreasury = _coneTreasury;
    }

    /// @notice initialize storage variables on a new G-UNI pool, only called once
    /// @param _name name of Vault (immutable)
    /// @param _symbol symbol of Vault (immutable)
    /// @param _pool address of Uniswap V3 pool (immutable)
    /// @param _managerFeeBPS proportion of fees earned that go to manager treasury
    /// @param _lowerTick initial lowerTick (only changeable with executiveRebalance)
    /// @param _lowerTick initial upperTick (only changeable with executiveRebalance)
    /// @param _manager_ address of manager (ownership can be transferred)
    /// @param _percentageBIPS percentage of liquidity in each range
    function initialize(
        string memory _name,
        string memory _symbol,
        address _pool,
        uint16 _managerFeeBPS,
        int24[] calldata _lowerTick,
        int24[] calldata _upperTick,
        address _manager_,
        uint256[] calldata _percentageBIPS
    ) external initializer {
        coneFeeBPS = 2000;
        require(_managerFeeBPS <= 10000 - coneFeeBPS);

        // these variables are immutable after initialization
        pool = IAlgebraPool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        // these variables can be udpated by the manager
        _manager = _manager_;
        managerFeeBPS = _managerFeeBPS;
        managerTreasury = _manager_; // default: treasury is admin

        lowerTicks[RangeType.Near] = _lowerTick[0];
        lowerTicks[RangeType.Medium] = _lowerTick[1];
        lowerTicks[RangeType.Far] = _lowerTick[2];

        upperTicks[RangeType.Near] = _upperTick[0];
        upperTicks[RangeType.Medium] = _upperTick[1];
        upperTicks[RangeType.Far] = _upperTick[2];
        if(_percentageBIPS.length != 3 || _percentageBIPS[0] + _percentageBIPS[1] + _percentageBIPS[2] != 10000) {
           revert Invalid_Percentage_BIPS();
        }
        percentageBIPS[RangeType.Near] = _percentageBIPS[0];
        percentageBIPS[RangeType.Medium] = _percentageBIPS[1];
        percentageBIPS[RangeType.Far] = _percentageBIPS[2];
        // these variables can be updated by the manager
        minLiquidityToMint = 1000;
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();
    }

    /// @notice change configurable external parameters, only manager can call
    /// @param newConeFeeBPS Basis Points of fees earned credited to cone (negative to ignore)
    /// @param newManagerFeeBPS Basis Points of fees earned credited to manager (negative to ignore)
    /// @param newManagerTreasury address that collects manager fees (Zero address to ignore)
    // solhint-disable-next-line code-complexity
    function updateManagerParams(
        int16 newConeFeeBPS,
        int16 newManagerFeeBPS,
        address newManagerTreasury
    ) external onlyManager {
        require(newManagerFeeBPS <= 10000 - newConeFeeBPS);
        require(newConeFeeBPS <= 5000 && newManagerFeeBPS <= 5000, "Cannot set fees above 50%");
        uint256 fee0;
        uint256 fee1;
        for (uint256 i = 0; i < 3; ++i) {
            (,, uint256 _fee0, uint256 _fee1) = _withdraw(lowerTicks[RangeType(i)], upperTicks[RangeType(i)], 0);
            fee0 += _fee0;
            fee1 += _fee1;
        }
        (fee0, fee1) = _applyFees(fee0, fee1);
        emit FeesEarned(fee0, fee1);
        if (newManagerFeeBPS >= 0) managerFeeBPS = uint16(newManagerFeeBPS);
        if (newConeFeeBPS >= 0) coneFeeBPS = uint16(newConeFeeBPS);
        if (address(0) != newManagerTreasury) {
            managerTreasury = newManagerTreasury;
        }
        emit UpdateManagerParams(
            coneFeeBPS,
            managerFeeBPS,
            managerTreasury
        );
    }

    function toggleRestrictMint() external onlyManager {
        if (restrictedMintToggle == RESTRICTED_MINT_ENABLED) {
            restrictedMintToggle = 0;
        } else {
            restrictedMintToggle = RESTRICTED_MINT_ENABLED;
        }
    }

    /// @notice set the minimum liquidity to mint
    /// @param _minLiquidityToMint minimum liquidity to mint
    function setMinLiquidityToMint(uint128 _minLiquidityToMint) external onlyManager {
        minLiquidityToMint = _minLiquidityToMint;
    }

    /// @notice withdraw cone fees accrued
    function withdrawConeBalance() external {
        uint256 amount0 = coneBalance0;
        uint256 amount1 = coneBalance1;

        coneBalance0 = 0;
        coneBalance1 = 0;

        if (amount0 > 0) {
            token0.safeTransfer(coneTreasury, amount0);
        }

        if (amount1 > 0) {
            token1.safeTransfer(coneTreasury, amount1);
        }
    }

    // functions => Automatically called Externally

    function _applyFees(uint256 _fee0, uint256 _fee1) internal returns (uint256 fee0, uint256 fee1) {
        (
            coneBalance0,
            coneBalance1,
            managerBalance0,
            managerBalance1,fee0,fee1
        ) = ConeCamelotLibrary.applyFees(address(this), _fee0, _fee1);
        emit CollectedFees(_fee0, _fee1);
        return (fee0, fee1);
    }

    // solhint-disable-next-line function-max-lines
    function _withdraw(
        int24 lowerTick_,
        int24 upperTick_,
        uint128 liquidity
    )
        internal
        returns (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1)
    {
        uint256 preBalance0 = token0.balanceOf(address(this));
        uint256 preBalance1 = token1.balanceOf(address(this));

        (burn0, burn1) = pool.burn(lowerTick_, upperTick_, liquidity);
        pool.collect(
            address(this),
            lowerTick_,
            upperTick_,
            type(uint128).max,
            type(uint128).max
        );
        fee0 = token0.balanceOf(address(this)) - preBalance0 - burn0;
        fee1 = token1.balanceOf(address(this)) - preBalance1 - burn1;
    }

    // solhint-disable-next-line function-max-lines
    function _deposit(
        int24 lowerTick_,
        int24 upperTick_,
        uint256 amount0,
        uint256 amount1,
        uint160 swapThresholdPrice,
        uint256 swapAmountBPS,
        bool zeroForOne
    ) internal {
        (uint256 amount0Deposited, uint256 amount1Deposited) = _rebalanceMint(
            lowerTick_,
            upperTick_,
            amount0,
            amount1
        );
        amount0 -= amount0Deposited;
        amount1 -= amount1Deposited;
        int256 swapAmount = SafeCast.toInt256(
            ((zeroForOne ? amount0 : amount1) * swapAmountBPS) / 10000
        );
        if (swapAmount > 0) {
            _swapAndDeposit(
                lowerTick_,
                upperTick_,
                amount0,
                amount1,
                swapAmount,
                swapThresholdPrice,
                zeroForOne
            );
        }
    }

    function _swapAndDeposit(
        int24 lowerTick_,
        int24 upperTick_,
        uint256 amount0,
        uint256 amount1,
        int256 swapAmount,
        uint160 swapThresholdPrice,
        bool zeroForOne
    ) internal returns (uint256 finalAmount0, uint256 finalAmount1) {
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            zeroForOne,
            swapAmount,
            swapThresholdPrice,
            ""
        );
        finalAmount0 = uint256(SafeCast.toInt256(amount0) - amount0Delta);
        finalAmount1 = uint256(SafeCast.toInt256(amount1) - amount1Delta);
        if (finalAmount0 > 0 || finalAmount1 > 0) {
                 _rebalanceMint(
                    lowerTick_,
                    upperTick_,
                    finalAmount0,
                    finalAmount1
                );
        }
    }

    function _rebalanceMint(
        int24 lowerTick_,
        int24 upperTick_,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 amount0Deposited, uint256 amount1Deposited) {
        // Add liquidity a second time
        (uint160 sqrtRatioX96, , , , , , , ) = pool.globalState();
        uint128 liquidityAfterSwap = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTick_.getSqrtRatioAtTick(),
            upperTick_.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        if (liquidityAfterSwap > 0) {
            (amount0Deposited, amount1Deposited, ) = pool.mint(
                address(this),
                address(this),
                lowerTick_,
                upperTick_,
                liquidityAfterSwap,
                ""
            );
        }
    }
}


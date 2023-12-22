//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {IPancakeV3MintCallback} from "./IPancakeV3MintCallback.sol";
import {IPancakeV3SwapCallback} from "./IPancakeV3SwapCallback.sol";
import {IPancakeV3Pool} from "./IPancakeV3Pool.sol";
import {DataTypes} from "./DataTypes.sol";

interface IRangeProtocolVault is IERC20Upgradeable, IPancakeV3MintCallback, IPancakeV3SwapCallback {
    // EVENTS
    event Minted(
        address indexed receiver,
        uint256 mintAmount,
        uint256 amount0In,
        uint256 amount1In
    );
    event Burned(
        address indexed receiver,
        uint256 burnAmount,
        uint256 amount0Out,
        uint256 amount1Out
    );
    event LiquidityAdded(
        uint256 liquidityMinted,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0In,
        uint256 amount1In
    );
    event LiquidityRemoved(
        uint256 liquidityRemoved,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Out,
        uint256 amount1Out
    );
    event FeesEarned(uint256 feesEarned0, uint256 feesEarned1);
    event FeesUpdated(uint16 managingFee, uint16 performanceFee, uint16 otherFee);
    event InThePositionStatusSet(bool inThePosition);
    event Swapped(bool zeroForOne, int256 amount0, int256 amount1);
    event TicksSet(int24 lowerTick, int24 upperTick);
    event MintStarted();
    event OtherFeeRecipientSet(address otherFeeRecipient);

    // GETTER FUNCTIONS
    function lowerTick() external view returns (int24);

    function upperTick() external view returns (int24);

    function inThePosition() external view returns (bool);

    function mintStarted() external view returns (bool);

    function tickSpacing() external view returns (int24);

    function pool() external view returns (IPancakeV3Pool);

    function token0() external view returns (IERC20Upgradeable);

    function token1() external view returns (IERC20Upgradeable);

    function factory() external view returns (address);

    function managingFee() external view returns (uint16);

    function performanceFee() external view returns (uint16);

    function managerBalance0() external view returns (uint256);

    function managerBalance1() external view returns (uint256);

    function userVaults(address user) external view returns (DataTypes.UserVault memory);

    function users(uint256 index) external view returns (address);

    function WETH9() external view returns (address);

    function getUserVaults(
        uint256 fromIdx,
        uint256 toIdx
    ) external view returns (DataTypes.UserVaultInfo[] memory);

    function getMintAmounts(
        uint256 amount0Max,
        uint256 amount1Max
    ) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount);

    function getUnderlyingBalances()
        external
        view
        returns (uint256 amount0Current, uint256 amount1Current);

    function getCurrentFees() external view returns (uint256 fee0, uint256 fee1);

    function getPositionID() external view returns (bytes32 positionID);

    function userCount() external view returns (uint256);

    function priceOracle0() external view returns (address);

    function priceOracle1() external view returns (address);

    function lastRebalanceTimestamp() external view returns (uint256);

    function otherFee() external view returns (uint256);

    function otherFeeRecipient() external view returns (address);

    function otherBalance0() external view returns (uint256);

    function otherBalance1() external view returns (uint256);

    // STATE MODIFYING FUNCTIONS
    function initialize(address _pool, int24 _tickSpacing, bytes memory data) external;

    function updateTicks(int24 _lowerTick, int24 _upperTick) external;

    function mint(
        uint256 mintAmount,
        bool depositNative,
        uint256[2] calldata maxAmounts
    ) external payable returns (uint256 amount0, uint256 amount1);

    function burn(
        uint256 burnAmount,
        bool withdrawNative,
        uint256[2] calldata minAmounts
    ) external returns (uint256 amount0, uint256 amount1);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function removeLiquidity(uint256[2] calldata minAmounts) external;

    function swap(
        bool zeroForOne,
        int256 swapAmount,
        uint160 sqrtPriceLimitX96,
        uint256 minAmountIn
    ) external returns (int256 amount0, int256 amount1);

    function addLiquidity(
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 amount0,
        uint256 amount1,
        uint256[2] calldata maxAmounts
    ) external returns (uint256 remainingAmount0, uint256 remainingAmount1);

    function rebalance(
        address target,
        bytes calldata swapData,
        bool zeroForOne,
        uint256 amount
    ) external;

    function pullFeeFromPool() external;

    function collectManager() external;

    function collectOtherFee() external;

    function updateFees(
        uint16 newManagingFee,
        uint16 newPerformanceFee,
        uint16 newOtherFee
    ) external;
}


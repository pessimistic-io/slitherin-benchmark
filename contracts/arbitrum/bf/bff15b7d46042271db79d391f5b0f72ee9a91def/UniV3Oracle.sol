// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "./EnumerableSet.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./IUniV3Oracle.sol";
import "./FullMath.sol";
import "./TickMath.sol";
import "./ExceptionsLibrary.sol";
import "./CommonLibrary.sol";
import "./DefaultAccessControl.sol";
import "./ContractMeta.sol";

contract UniV3Oracle is ContractMeta, IUniV3Oracle, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IUniV3Oracle
    uint16 public constant LOW_OBS = 10; // >= 2.5 min
    /// @inheritdoc IUniV3Oracle
    uint16 public constant MID_OBS = 30; // >= 7.5 min
    /// @inheritdoc IUniV3Oracle
    uint16 public constant HIGH_OBS = 100; // >= 30 min

    /// @inheritdoc IUniV3Oracle
    IUniswapV3Factory public immutable factory;
    /// @inheritdoc IUniV3Oracle
    mapping(address => mapping(address => IUniswapV3Pool)) public poolsIndex;
    EnumerableSet.AddressSet private _pools;

    constructor(
        IUniswapV3Factory factory_,
        IUniswapV3Pool[] memory pools,
        address admin
    ) DefaultAccessControl(admin) {
        factory = factory_;
        _addUniV3Pools(pools);
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @inheritdoc IOracle
    function price(
        address token0,
        address token1,
        uint256 safetyIndicesSet
    ) external view returns (uint256[] memory pricesX96, uint256[] memory safetyIndices) {
        bool isSwapped = false;
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            isSwapped = true;
        }
        IUniswapV3Pool pool = poolsIndex[token0][token1];
        if (address(pool) == address(0)) {
            return (pricesX96, safetyIndices);
        }
        uint256[] memory sqrtPricesX96 = new uint256[](4);
        pricesX96 = new uint256[](4);
        safetyIndices = new uint256[](4);
        uint256 len = 0;
        (uint256 spotSqrtPriceX96, , uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(
            pool
        ).slot0();
        if (safetyIndicesSet & 0x2 > 0) {
            sqrtPricesX96[len] = spotSqrtPriceX96;
            safetyIndices[len] = 1;
            len += 1;
        }
        for (uint256 i = 2; i < 5; i++) {
            if (safetyIndicesSet & (1 << i) > 0) {
                uint16 bfAvg = _obsForSafety(i);
                if (observationCardinality <= bfAvg) {
                    continue;
                }
                uint256 obs1 = (uint256(observationIndex) + uint256(observationCardinality) - 1) %
                    uint256(observationCardinality);
                uint256 obs0 = (uint256(observationIndex) + uint256(observationCardinality) - bfAvg) %
                    uint256(observationCardinality);
                int256 tickAverage;
                {
                    (uint32 timestamp0, int56 tickCumulative0, , ) = IUniswapV3Pool(pool).observations(obs0);
                    (uint32 timestamp1, int56 tickCumulative1, , ) = IUniswapV3Pool(pool).observations(obs1);
                    require(timestamp0 < timestamp1, ExceptionsLibrary.INVALID_VALUE);
                    uint256 timespan = timestamp1 - timestamp0;
                    tickAverage = (int256(tickCumulative1) - int256(tickCumulative0)) / int256(timespan);
                }
                sqrtPricesX96[len] = TickMath.getSqrtRatioAtTick(int24(tickAverage));
                safetyIndices[len] = i;
                len += 1;
            }
        }
        assembly {
            mstore(pricesX96, len)
            mstore(safetyIndices, len)
        }
        for (uint256 i = 0; i < len; i++) {
            pricesX96[i] = FullMath.mulDiv(sqrtPricesX96[i], sqrtPricesX96[i], CommonLibrary.Q96);
            if (isSwapped) {
                pricesX96[i] = FullMath.mulDiv(CommonLibrary.Q96, CommonLibrary.Q96, pricesX96[i]);
            }
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IUniV3Oracle).interfaceId == interfaceId;
    }

    // -------------------------  EXTERNAL, MUTATING  ------------------------------

    /// @inheritdoc IUniV3Oracle
    function addUniV3Pools(IUniswapV3Pool[] memory pools) external {
        _requireAdmin();
        _addUniV3Pools(pools);
    }

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("UniV3Oracle");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _obsForSafety(uint256 safety) internal pure returns (uint16) {
        if (safety == 2) {
            return LOW_OBS;
        } else if (safety == 3) {
            return MID_OBS;
        } else {
            require(safety == 4, ExceptionsLibrary.INVALID_VALUE);
            return HIGH_OBS;
        }
    }

    function _addUniV3Pools(IUniswapV3Pool[] memory pools) internal {
        IUniswapV3Pool[] memory replaced = new IUniswapV3Pool[](pools.length);
        IUniswapV3Pool[] memory added = new IUniswapV3Pool[](pools.length);
        uint256 j;
        uint256 k;
        for (uint256 i = 0; i < pools.length; i++) {
            IUniswapV3Pool pool = pools[i];
            address token0 = pool.token0();
            address token1 = pool.token1();
            _pools.add(address(pool));
            IUniswapV3Pool currentPool = poolsIndex[token0][token1];
            if (address(currentPool) != address(0)) {
                replaced[j] = currentPool;
                j += 1;
            } else {
                added[k] = currentPool;
                k += 1;
            }
            poolsIndex[token0][token1] = pool;
        }
        assembly {
            mstore(replaced, j)
            mstore(added, k)
        }
        emit PoolsUpdated(tx.origin, msg.sender, added, replaced);
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when new pool is added or updated and become available for oracle prices
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param pools UniV3 pools added
    /// @param replacedPools UniV3 pools updated
    event PoolsUpdated(
        address indexed origin,
        address indexed sender,
        IUniswapV3Pool[] pools,
        IUniswapV3Pool[] replacedPools
    );
}


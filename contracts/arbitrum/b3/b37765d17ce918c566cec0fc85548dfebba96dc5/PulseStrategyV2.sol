// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./IUniswapV3Pool.sol";
import "./INonfungiblePositionManager.sol";
import "./IStrategy.sol";

import "./UniV3TokenRegistry.sol";

import "./IRebalanceFacet.sol";
import "./ICommonFacet.sol";

contract PulseStrategyV2 is IStrategy {
    using SafeERC20 for IERC20;

    struct ImmutableParams {
        address owner;
        address vault;
        IOracle oracle;
        IUniswapV3Pool pool;
    }

    struct MutableParams {
        int24 defaultIntervalWidth;
        int24 maxPositionLengthInTicks;
        uint256 neighborhoodFactorD;
        uint256 extensionFactorD;
        int24 maxDeviation;
        uint32 timespan;
    }

    struct Storage {
        ImmutableParams immutableParams;
        MutableParams mutableParams;
        VolatileParams volatileParams;
    }

    struct VolatileParams {
        address token;
        int24 prevTickLower;
        int24 prevTickUpper;
        bool forceRebalanceFlag;
        bool prevForceRebalanceFlag;
    }

    bytes32 internal constant STORAGE_POSITION = keccak256("strategy.storage");

    function contractStorage() internal pure returns (Storage storage ds) {
        bytes32 position = STORAGE_POSITION;

        assembly {
            ds.slot := position
        }
    }

    uint256 public constant Q96 = 2 ** 96;
    uint256 public constant D = 10 ** 9;

    INonfungiblePositionManager public immutable positionManager;
    UniV3TokenRegistry public immutable registry;

    constructor(INonfungiblePositionManager positionManager_, UniV3TokenRegistry registry_) {
        positionManager = positionManager_;
        registry = registry_;
    }

    function initialize(
        address owner,
        address vault,
        IUniswapV3Pool pool,
        IOracle oracle,
        string memory name,
        string memory symbol,
        MutableParams memory mutableParams_
    ) external {
        Storage storage s = contractStorage();
        require(s.immutableParams.owner == address(0));

        (, int24 tick, , , , , ) = pool.slot0();
        tick -= tick % pool.tickSpacing();

        int24 tickLower = tick - mutableParams_.defaultIntervalWidth / 2;
        int24 tickUpper = tick + mutableParams_.defaultIntervalWidth / 2;

        (, UniV3Token uniV3Token) = registry.createToken(
            abi.encode(
                pool.token0(),
                pool.token1(),
                pool.fee(),
                tickLower,
                tickUpper,
                "Mellow PulseV2 UniV3Token",
                "PulseUNI"
            )
        );

        address[] memory mutableTokens = new address[](1);
        mutableTokens[0] = address(uniV3Token);
        s.immutableParams = ImmutableParams({owner: owner, vault: vault, oracle: oracle, pool: pool});
        s.mutableParams = mutableParams_;
        s.volatileParams = VolatileParams({
            token: mutableTokens[0],
            prevTickLower: tickLower,
            prevTickUpper: tickUpper,
            forceRebalanceFlag: false,
            prevForceRebalanceFlag: false
        });

        ICommonFacet(vault).initializeCommonFacet(new address[](0), mutableTokens, oracle, name, symbol);
    }

    function _requirePoolStability() private view {
        Storage memory s = contractStorage();
        IUniswapV3Pool pool = s.immutableParams.pool;
        (, int24 spotTick, , , , , ) = pool.slot0();
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(address(pool), s.mutableParams.timespan);
        int24 delta = averageTick - spotTick;
        int24 maxDeviation = s.mutableParams.maxDeviation;
        require(!withFail && -maxDeviation <= delta && delta <= maxDeviation, "Pool is not stable");
    }

    function parameters()
        public
        pure
        returns (
            ImmutableParams memory immutableParams,
            MutableParams memory mutableParams,
            VolatileParams memory volatileParams
        )
    {
        Storage memory s = contractStorage();
        immutableParams = s.immutableParams;
        mutableParams = s.mutableParams;
        volatileParams = s.volatileParams;
    }

    function transferOwnership(address newOwner) external {
        Storage storage s = contractStorage();
        require(msg.sender == s.immutableParams.owner);
        s.immutableParams.owner = newOwner; // address(0) or some new user / contract
    }

    function updateMutableParams(MutableParams memory newMutableParams) external {
        Storage storage s = contractStorage();
        require(msg.sender == s.immutableParams.owner);

        require(
            newMutableParams.defaultIntervalWidth > 0 &&
                newMutableParams.maxPositionLengthInTicks > 0 &&
                newMutableParams.neighborhoodFactorD > 0 &&
                newMutableParams.extensionFactorD > 0 &&
                newMutableParams.maxDeviation > 0 &&
                newMutableParams.timespan > 0,
            "Zero value"
        );

        require(newMutableParams.neighborhoodFactorD < D, "Limit overflow");

        VolatileParams memory params = s.volatileParams;
        s.volatileParams = VolatileParams({
            token: params.token,
            prevTickLower: params.prevTickLower,
            prevTickUpper: params.prevTickUpper,
            forceRebalanceFlag: true,
            prevForceRebalanceFlag: false
        });

        s.mutableParams = newMutableParams;
    }

    function calculateNewPosition(
        int24 lowerTick,
        int24 upperTick,
        int24 spotTick,
        bool forceRebalanceFlag
    ) public view returns (int24 newTickLower, int24 newTickUpper) {
        Storage memory s = contractStorage();
        int24 tickSpacing = s.immutableParams.pool.tickSpacing();

        int24 width = upperTick - lowerTick;
        int24 prevTickNeighborhood = int24(
            uint24(FullMath.mulDiv(uint24(width), s.mutableParams.neighborhoodFactorD, D))
        );

        if (forceRebalanceFlag) {
            int24 centralTick = spotTick - (spotTick % tickSpacing);
            if ((spotTick % tickSpacing) * 2 > tickSpacing) {
                centralTick += tickSpacing;
            }
            newTickLower = centralTick - s.mutableParams.defaultIntervalWidth / 2;
            newTickUpper = centralTick + s.mutableParams.defaultIntervalWidth / 2;
            return (newTickLower, newTickUpper);
        }

        if (lowerTick + prevTickNeighborhood <= spotTick && spotTick <= upperTick - prevTickNeighborhood) {
            return (lowerTick, upperTick);
        }

        int24 closenessToLower = lowerTick + prevTickNeighborhood - spotTick;
        int24 closenessToUpper = spotTick - upperTick - prevTickNeighborhood;

        int24 closeness = closenessToLower;
        if (closenessToUpper > closenessToLower) {
            closeness = closenessToUpper;
        }

        int24 sideExtension = closeness +
            int24(int256(FullMath.mulDiv(uint24(prevTickNeighborhood), s.mutableParams.extensionFactorD, D)));
        if (sideExtension % tickSpacing != 0 || sideExtension == 0) {
            sideExtension += tickSpacing;
            sideExtension -= sideExtension % tickSpacing;
        }

        newTickLower = lowerTick - sideExtension;
        newTickUpper = upperTick + sideExtension;

        if (newTickUpper - newTickLower > s.mutableParams.maxPositionLengthInTicks) {
            int24 centralTick = spotTick - (spotTick % tickSpacing);
            if ((spotTick % tickSpacing) * 2 > tickSpacing) {
                centralTick += tickSpacing;
            }
            newTickLower = centralTick - s.mutableParams.defaultIntervalWidth / 2;
            newTickUpper = centralTick + s.mutableParams.defaultIntervalWidth / 2;
        }
    }

    function checkStateAfterRebalance() external view returns (bool) {
        _requirePoolStability();
        Storage memory s = contractStorage();
        VolatileParams memory volatileParams = s.volatileParams;
        IUniswapV3Pool pool = s.immutableParams.pool;
        (, int24 spotTick, , , , , ) = pool.slot0();
        int24 prevTickLower = volatileParams.prevTickLower;
        int24 prevTickUpper = volatileParams.prevTickUpper;

        (int24 newTickLower, int24 newTickUpper) = calculateNewPosition(
            prevTickLower,
            prevTickUpper,
            spotTick,
            s.volatileParams.prevForceRebalanceFlag
        );

        UniV3Token currentToken = UniV3Token(volatileParams.token);

        int24 tickLower = currentToken.tickLower();
        int24 tickUpper = currentToken.tickUpper();
        int24 tickSpacing = currentToken.pool().tickSpacing();

        return
            tickUpper - currentToken.tickLower() == newTickUpper - newTickLower &&
            (tickLower == newTickLower ||
                tickLower + tickSpacing == newTickLower ||
                tickLower - tickSpacing == newTickLower);
    }

    function canStartAuction() external view returns (bool) {
        _requirePoolStability();
        Storage memory s = contractStorage();
        (, int24 spotTick, , , , , ) = s.immutableParams.pool.slot0();
        UniV3Token token = UniV3Token(s.volatileParams.token);
        int24 tickLower = token.tickLower();
        int24 tickUpper = token.tickUpper();

        int24 width = tickUpper - tickLower;
        int24 tickNeighborhood = int24(uint24(FullMath.mulDiv(uint24(width), s.mutableParams.neighborhoodFactorD, D)));
        if (
            tickLower + tickNeighborhood <= spotTick &&
            spotTick <= tickUpper - tickNeighborhood &&
            !s.volatileParams.forceRebalanceFlag
        ) {
            return false;
        }
        return true;
    }

    function canStopAuction() external view returns (bool) {
        _requirePoolStability();
        Storage memory s = contractStorage();
        (, int24 spotTick, , , , , ) = s.immutableParams.pool.slot0();
        UniV3Token token = UniV3Token(s.volatileParams.token);
        int24 tickLower = token.tickLower();
        int24 tickUpper = token.tickUpper();

        int24 width = tickUpper - tickLower;
        int24 tickNeighborhood = int24(uint24(FullMath.mulDiv(uint24(width), s.mutableParams.neighborhoodFactorD, D)));
        if (
            tickLower + tickNeighborhood * 2 <= spotTick &&
            spotTick <= tickUpper - tickNeighborhood * 2 &&
            !s.volatileParams.forceRebalanceFlag
        ) {
            return true;
        }
        return false;
    }

    function setForceRebalanceFlag() external {
        Storage storage s = contractStorage();
        require(msg.sender == s.immutableParams.owner);
        VolatileParams memory params = s.volatileParams;
        s.volatileParams = VolatileParams({
            token: params.token,
            prevTickLower: params.prevTickLower,
            prevTickUpper: params.prevTickUpper,
            forceRebalanceFlag: true,
            prevForceRebalanceFlag: false
        });
    }

    function updateVaultTokens(address[] memory vaultTokens) external {
        Storage storage s = contractStorage();
        require(msg.sender == s.immutableParams.vault);

        UniV3Token newToken = UniV3Token(vaultTokens[0]);
        UniV3Token prevToken = UniV3Token(s.volatileParams.token);
        int24 prevTickLower = 0;
        int24 prevTickUpper = 0;
        if (address(prevToken) != address(0)) {
            prevTickLower = prevToken.tickLower();
            prevTickUpper = prevToken.tickUpper();
        }
        s.volatileParams = VolatileParams({
            token: address(newToken),
            prevTickLower: prevTickLower,
            prevTickUpper: prevTickUpper,
            forceRebalanceFlag: false,
            prevForceRebalanceFlag: s.volatileParams.forceRebalanceFlag
        });
    }
}


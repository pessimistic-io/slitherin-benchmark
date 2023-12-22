// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IV3Pool} from "./IV3Pool.sol";
import {IAlcorOptionPoolFactory} from "./IAlcorOptionPoolFactory.sol";
import {IBaseAlcorOptionCore} from "./IBaseAlcorOptionCore.sol";

import {EnumerableSet} from "./EnumerableSet.sol";

import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {AlcorUtils} from "./AlcorUtils.sol";

import {VanillaOptionPool} from "./VanillaOptionPool.sol";
import {LPPosition} from "./LPPosition.sol";

abstract contract BaseAlcorOptionCore is IBaseAlcorOptionCore {
    // for getting info of the LP position
    using LPPosition for mapping(bytes32 => LPPosition.Info);
    // for getting the LP positions hashes or adding/removing LP position hash
    using LPPosition for mapping(address owner => mapping(bytes32 optionPoolKeyHash => EnumerableSet.Bytes32Set));
    using LPPosition for mapping(bytes32 lpPositionHash => LPPosition.PositionTicks);
    // for getting and updating options balances
    using VanillaOptionPool for mapping(address owner => mapping(bytes32 optionPoolKeyHash => int256));
    // for getting info of the option pool
    using VanillaOptionPool for VanillaOptionPool.Key;

    ///// errors
    error ZeroLiquidity();
    error alreadyMinted();
    error notEntireBurn();

    address public immutable token0;
    address public immutable token1;
    IV3Pool public immutable v3Pool;

    mapping(address owner => mapping(bytes32 optionPoolKeyHash => EnumerableSet.Bytes32Set))
        internal userLPpositionsKeyHashes;
    mapping(bytes32 lpPositionKeyHash => LPPosition.Info)
        public LPpositionInfos;

    mapping(bytes32 lpPositionHash => LPPosition.PositionTicks) lpPositionsTicksInfos;

    string constant USDC = "USDC";

    constructor(address _V3Pool) {
        v3Pool = IV3Pool(_V3Pool);
        token0 = v3Pool.token0();
        token1 = v3Pool.token1();
    }

    struct UserLLPositionInfoExpanded {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 deposit_amount0;
        uint256 deposit_amount1;
    }

    ///// used by front-end
    function getUserLPPositionsInfos(
        address owner,
        VanillaOptionPool.Key memory optionPoolKey
    )
        external
        view
        returns (UserLLPositionInfoExpanded[] memory userLPPositionsExpanded)
    {
        bytes32[] memory positionsKeys = userLPpositionsKeyHashes.getValues(
            owner,
            optionPoolKey
        );
        userLPPositionsExpanded = new UserLLPositionInfoExpanded[](
            positionsKeys.length
        );

        LPPosition.Info memory lpPositionInfo;
        for (uint i = 0; i < positionsKeys.length; i++) {
            lpPositionInfo = LPpositionInfos[positionsKeys[i]];
            userLPPositionsExpanded[i] = UserLLPositionInfoExpanded({
                tickLower: lpPositionsTicksInfos[positionsKeys[i]].tickLower,
                tickUpper: lpPositionsTicksInfos[positionsKeys[i]].tickUpper,
                liquidity: lpPositionInfo.liquidity,
                deposit_amount0: lpPositionInfo.deposit_amount0,
                deposit_amount1: lpPositionInfo.deposit_amount1
            });
        }
        return userLPPositionsExpanded;
    }

    // @dev mints or burns user's entire position
    // @dev liquidity > 0 if mint position, liquidity < 0 otherwise
    function _modifyPosition(
        LPPosition.Key memory lpPositionKey,
        int128 liquidity,
        int256 amount0Delta,
        int256 amount1Delta
    )
        internal
        returns (
            uint256 amount0ToTransfer,
            uint256 amount1ToTransfer,
            int256 userOptionBalanceDelta
        )
    {
        if (liquidity == 0) revert ZeroLiquidity();
        LPPosition.Info storage _position = LPpositionInfos.get(lpPositionKey);
        if (liquidity < 0 && (_position.liquidity != uint128(-liquidity)))
            revert notEntireBurn();
        if (liquidity > 0 && (_position.liquidity > 0)) revert alreadyMinted();

        // change deposit amounts
        // case of mint
        if (liquidity > 0) {
            LPpositionInfos.create(
                lpPositionKey,
                uint128(liquidity),
                uint256(amount0Delta),
                uint256(amount1Delta)
            );
            userLPpositionsKeyHashes.addPos(lpPositionKey);
            lpPositionsTicksInfos.updateTicksInfos(lpPositionKey);
        }
        // case of burn
        else {
            // update user's options balance
            userOptionBalanceDelta = (-amount1Delta -
                int256(_position.deposit_amount1));

            // transfer dollarts to the owner
            // ERC20(token0).safeTransfer(owner, uint256(-amount0Delta));
            amount0ToTransfer = uint256(-amount0Delta);
            // transfer the collateral to the owner

            // case of bought call options
            if (_position.deposit_amount0 > uint256(-amount0Delta)) {
                // transfer only the collateral that was provided when position was minted
                amount1ToTransfer = _position.deposit_amount1;
            }
            // case of sold call options
            else if (_position.deposit_amount0 <= uint256(-amount0Delta)) {
                // transfer all left collateral
                amount1ToTransfer = uint256(-amount1Delta);
            }

            // clear the LP position
            // delete LPpositionInfos[positionKey];
            LPpositionInfos.clear(lpPositionKey);
            userLPpositionsKeyHashes.removePos(lpPositionKey);
            lpPositionsTicksInfos.clearTicksInfos(lpPositionKey);
        }
    }

    // @dev this function allows to provide liquidity to the option pool
    // @param address of position owner
    // @param tickLower is the lower tick of option price range
    // @param tickUpper is the upper tick of option price range
    // @param amount is amount of liquidity in terms of uniswap v3
    function _mintLP(
        LPPosition.Key memory lpPositionKey,
        uint128 amount
    ) internal returns (uint256 amount0Delta, uint256 amount1Delta) {
        bytes32 optionPoolKeyHash = VanillaOptionPool
            .Key({
                expiry: lpPositionKey.expiry, //
                strike: lpPositionKey.strike,
                isCall: lpPositionKey.isCall
            })
            .hashOptionPool();

        // inverse the ticks
        (lpPositionKey.tickLower, lpPositionKey.tickUpper) = (
            -lpPositionKey.tickUpper,
            -lpPositionKey.tickLower
        );

        // amount0, amount1 are amounts deltas
        (amount0Delta, amount1Delta) = v3Pool.mint(
            lpPositionKey.owner,
            optionPoolKeyHash,
            lpPositionKey.tickLower,
            lpPositionKey.tickUpper,
            amount,
            abi.encode()
        );

        // if the position is already minted (i.e. liquidity > 0), revert
        if (LPpositionInfos.get(lpPositionKey).liquidity > 0)
            revert alreadyMinted();

        // we do not need the return amount of _modifyPosition because it's mintLP
        _modifyPosition(
            lpPositionKey,
            int128(amount),
            int256(amount0Delta),
            int256(amount1Delta)
        );
    }

    // @dev this function burns the option LP position
    // @dev we don't need whenNotExpired modifier here as user should be able to burn at any time
    // @param address of position owner
    // @param tickLower is the lower tick of option price range
    // @param tickUpper is the upper tick of option price range
    // @param amount is amount of liquidity in terms of uniswap v3
    function _burnLP(
        LPPosition.Key memory lpPositionKey,
        uint128 amount
    )
        internal
        returns (
            uint256 amount0ToTransfer,
            uint256 amount1ToTransfer,
            int256 userOptionBalanceDelta
        )
    {
        bytes32 optionPoolKeyHash = VanillaOptionPool
            .Key({
                expiry: lpPositionKey.expiry, //
                strike: lpPositionKey.strike,
                isCall: lpPositionKey.isCall
            })
            .hashOptionPool();

        // inverse the ticks
        (lpPositionKey.tickLower, lpPositionKey.tickUpper) = (
            -lpPositionKey.tickUpper,
            -lpPositionKey.tickLower
        );

        (uint256 amount0Delta, uint256 amount1Delta) = v3Pool.burn(
            lpPositionKey.owner,
            optionPoolKeyHash,
            lpPositionKey.tickLower,
            lpPositionKey.tickUpper,
            amount
        );

        (
            amount0ToTransfer,
            amount1ToTransfer,
            userOptionBalanceDelta
        ) = _modifyPosition(
            lpPositionKey,
            -int128(amount),
            -int256(amount0Delta),
            -int256(amount1Delta)
        );
    }
}


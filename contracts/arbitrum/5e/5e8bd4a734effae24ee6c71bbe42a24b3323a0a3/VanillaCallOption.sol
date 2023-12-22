// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {BaseComboOption} from "./BaseComboOption.sol";
import {AlcorUtils} from "./AlcorUtils.sol";
import {VanillaOptionPool} from "./VanillaOptionPool.sol";
import {LPPosition} from "./LPPosition.sol";
import {OptionBalanceMath} from "./OptionBalanceMath.sol";
import {FullMath} from "./FullMath.sol";
import {TickMath} from "./TickMath.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {ERC20} from "./ERC20.sol";

import {BaseAlcorOptionCore} from "./BaseAlcorOptionCore.sol";

import {IVanillaOption} from "./IVanillaOption.sol";
import {IV3Pool} from "./IV3Pool.sol";
import {IV3PoolActions} from "./IV3PoolActions.sol";

import {console} from "./console.sol";

contract VanillaCallOption is
    BaseAlcorOptionCore,
    BaseComboOption,
    IVanillaOption
{
    using FullMath for uint256;
    using SafeERC20 for ERC20;
    using VanillaOptionPool for VanillaOptionPool.Key;
    using OptionBalanceMath for mapping(address owner => mapping(bytes32 optionPoolKeyHash => int256));

    bool private constant OPTION_TYPE_CALL = true;

    constructor(
        address _V3Pool,
        string memory _comboOptionName
    )
        BaseComboOption(_comboOptionName, OPTION_TYPE_CALL)
        BaseAlcorOptionCore(_V3Pool)
    {}

    struct OptionPoolInfoView {
        uint256 expiry;
        uint256 strike;
        bool isCall;
        uint256 sqrtPriceX96;
        uint256 token0Balance;
        uint256 token1Balance;
    }

    // used by front-end
    // todo: change 'isCall' to 'optionsTypeIsCall'
    function getOptionPoolsInfoForExpiry(
        uint256 expiry,
        bool isCall
    ) external view returns (OptionPoolInfoView[] memory) {
        uint256[] memory strikes = v3Pool.getAvailableStrikes(expiry, isCall);

        OptionPoolInfoView[] memory optionPoolsInfos = new OptionPoolInfoView[](
            strikes.length
        );

        bytes32 optionPoolKeyHash;
        uint160 sqrtPriceX96;
        for (uint16 i = 0; i < strikes.length; i++) {
            optionPoolKeyHash = VanillaOptionPool
                .Key({expiry: expiry, strike: strikes[i], isCall: isCall})
                .hashOptionPool();
            (sqrtPriceX96, , ) = v3Pool.slots0(optionPoolKeyHash);
            (uint256 token0Balance, uint256 token1Balance) = v3Pool
                .poolsBalances(optionPoolKeyHash);
            optionPoolsInfos[i] = OptionPoolInfoView({
                expiry: expiry,
                strike: strikes[i],
                isCall: isCall,
                sqrtPriceX96: sqrtPriceX96,
                token0Balance: token0Balance,
                token1Balance: token1Balance
            });
        }
        return optionPoolsInfos;
    }

    function initializeWithTick(
        VanillaOptionPool.Key memory optionPoolKey,
        int24 tick
    ) external {
        checkOptionType(optionPoolKey.isCall);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(-tick);

        // if uni pool was already initialized, this will revert
        v3Pool.initialize(
            optionPoolKey.expiry,
            optionPoolKey.strike,
            optionPoolKey.isCall,
            sqrtPriceX96
        );

        emit AlcorInitOptionPool(
            optionPoolKey.expiry,
            optionPoolKey.strike,
            optionPoolKey.isCall,
            tick
        );
    }

    // @dev external mint function
    function mint(
        LPPosition.Key memory lpPositionKey,
        uint128 amount
    ) external lock returns (uint256 amount0Delta, uint256 amount1Delta) {
        checkOptionType(lpPositionKey.isCall);
        if (msg.sender != lpPositionKey.owner) revert notOwner();

        (amount0Delta, amount1Delta) = _mintLP(lpPositionKey, amount);

        // receive the funds from user and transfer to v3Pool
        ERC20(token0).safeTransferFrom(
            lpPositionKey.owner,
            address(v3Pool),
            amount0Delta
        );
        ERC20(token1).safeTransferFrom(
            lpPositionKey.owner,
            address(v3Pool),
            amount1Delta
        );

        v3Pool.updatePoolBalances(
            VanillaOptionPool
                .Key({
                    expiry: lpPositionKey.expiry,
                    strike: lpPositionKey.strike,
                    isCall: lpPositionKey.isCall
                })
                .hashOptionPool(),
            int256(amount0Delta),
            int256(amount1Delta)
        );

        emit AlcorMint(lpPositionKey.owner, amount0Delta, amount1Delta);
    }

    // @dev external burn function
    function burn(
        LPPosition.Key memory lpPositionKey,
        uint128 amount
    )
        external
        lock
        returns (
            uint256 amount0ToTransfer,
            uint256 amount1ToTransfer,
            int256 userOptionBalanceDelta
        )
    {
        checkOptionType(lpPositionKey.isCall);
        if (lpPositionKey.owner != msg.sender) revert notOwner();

        VanillaOptionPool.Key memory optionPoolKey = VanillaOptionPool.Key({
            expiry: lpPositionKey.expiry,
            strike: lpPositionKey.strike,
            isCall: lpPositionKey.isCall
        });

        (
            amount0ToTransfer,
            amount1ToTransfer,
            userOptionBalanceDelta
        ) = _burnLP(lpPositionKey, amount);

        usersBalances.updateOptionBalance(
            lpPositionKey.owner,
            optionPoolKey.hashOptionPool(),
            userOptionBalanceDelta
        );

        if (amount0ToTransfer > 0)
            v3Pool.transferFromPool(
                token0,
                lpPositionKey.owner,
                amount0ToTransfer
            );
        if (amount1ToTransfer > 0)
            v3Pool.transferFromPool(
                token1,
                lpPositionKey.owner,
                amount1ToTransfer
            );

        v3Pool.updatePoolBalances(
            optionPoolKey.hashOptionPool(),
            -int256(amount0ToTransfer),
            -int256(amount1ToTransfer)
        );

        emit AlcorBurn(
            lpPositionKey.owner,
            amount0ToTransfer,
            amount1ToTransfer
        );
    }

    // @dev this function allows to collect the spread fees accrued by user's LP position
    // @dev we don't need whenNotExpired modifier here as user should be able to collect fees at any time
    function collectFees(
        VanillaOptionPool.Key memory optionPoolKey,
        int24 tickLower,
        int24 tickUpper
    ) external lock returns (uint128 amount0, uint128 amount1) {
        checkOptionType(optionPoolKey.isCall);

        // first off, we update fees growth inside the position
        v3Pool.burn(
            msg.sender,
            optionPoolKey.hashOptionPool(),
            -tickUpper,
            -tickLower,
            0
        );

        // collect fees
        (amount0, amount1) = v3Pool.collect(
            msg.sender,
            optionPoolKey.hashOptionPool(),
            -tickUpper,
            -tickLower,
            type(uint128).max,
            type(uint128).max
        );

        // do transfers
        v3Pool.transferFromPool(token0, msg.sender, amount0);
        v3Pool.transferFromPool(token1, msg.sender, amount1);

        v3Pool.updatePoolBalances(
            optionPoolKey.hashOptionPool(),
            -int128(amount0),
            -int128(amount1)
        );

        emit AlcorCollect(msg.sender, amount0, amount1);
    }

    function swap(
        VanillaOptionPool.Key memory optionPoolKey,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        external
        lock
        returns (
            int256 amount0PoolShouldTransfer,
            int256 amount1PoolShouldTransfer
        )
    {
        checkOptionType(optionPoolKey.isCall);

        if (
            !((zeroForOne && amountSpecified < 0) ||
                (!zeroForOne && amountSpecified > 0))
        ) revert incorrectDirections();

        address owner = msg.sender;

        uint24 fee = v3Pool.fee();

        // swap
        (int256 amount0, int256 amount1) = v3Pool.swap(
            IV3PoolActions.SwapInputs({
                optionPoolKeyHash: optionPoolKey.hashOptionPool(),
                zeroForOne: zeroForOne,
                amountSpecified: zeroForOne
                    ? amountSpecified // if there's overflow it will revert, max fee amount is 1e5 (see V3Pool.sol)
                    : (amountSpecified * (int24(fee) + 1e6)) / 1e6,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );

        int256 userOptionBalance = usersBalances.getOptionBalance(
            owner,
            optionPoolKey.hashOptionPool()
        );

        (
            amount0PoolShouldTransfer,
            amount1PoolShouldTransfer
        ) = OptionBalanceMath.calculateNewOptionBalance(
            userOptionBalance,
            amount0,
            amountSpecified
        );

        // transfer token0
        if (amount0PoolShouldTransfer < 0)
            ERC20(token0).safeTransferFrom(
                owner,
                address(v3Pool),
                uint256(-amount0PoolShouldTransfer)
            );
        else if (amount0PoolShouldTransfer > 0)
            v3Pool.transferFromPool(
                token0,
                owner,
                uint256(amount0PoolShouldTransfer)
            );
        // transfer token1
        if (amount1PoolShouldTransfer < 0)
            ERC20(token1).safeTransferFrom(
                owner,
                address(v3Pool),
                uint256(-amount1PoolShouldTransfer)
            );
        else if (amount1PoolShouldTransfer > 0)
            v3Pool.transferFromPool(
                token1,
                owner,
                uint256(amount1PoolShouldTransfer)
            );

        if (!zeroForOne) {
            // transfer from user additional token1 fee
            ERC20(token1).safeTransferFrom(
                owner,
                address(v3Pool),
                // if there's overflow it will revert, max fee amount is 1e5 (see V3Pool.sol)
                (uint256(
                    amountSpecified > 0 ? amountSpecified : -amountSpecified
                ) * fee) / 1e6
            );
        }

        // update user's option balance
        usersBalances.updateOptionBalance(
            owner,
            optionPoolKey.hashOptionPool(),
            -amountSpecified
        );

        // console.logInt(
        //     usersBalances.getOptionBalance(
        //         owner,
        //         optionPoolKey.hashOptionPool()
        //     )
        // );

        console.logInt(int256(amount0PoolShouldTransfer));
        console.logInt(int256(amount1PoolShouldTransfer));

        v3Pool.updatePoolBalances(
            optionPoolKey.hashOptionPool(),
            -int256(amount0PoolShouldTransfer),
            -int256(amount1PoolShouldTransfer)
        );

        emit AlcorSwap(owner, amount0, amountSpecified);
    }

    // @dev this function allows to either exercise a call option or withdraw a collateral
    function withdraw(
        VanillaOptionPool.Key memory optionPoolKey
    ) external lock returns (uint256 amount) {
        checkOptionType(optionPoolKey.isCall);

        address owner = msg.sender;
        int256 userOptionBalance = usersBalances.getOptionBalance(
            owner,
            optionPoolKey.hashOptionPool()
        );
        if (userOptionBalance == 0) revert zeroOptionBalance();

        uint256 priceAtExpiry = v3Pool.pricesAtExpiries(optionPoolKey.expiry);

        // case of sold call options
        if (userOptionBalance < 0) {
            amount = uint256(-userOptionBalance).mulDiv(
                VanillaOptionPool.calculateVanillaCallPayoffInAsset(
                    false,
                    optionPoolKey.strike,
                    priceAtExpiry,
                    ERC20(token1).decimals()
                ),
                1 ether
            );
        }
        // case of bought call options
        else {
            amount = uint256(userOptionBalance).mulDiv(
                VanillaOptionPool.calculateVanillaCallPayoffInAsset(
                    true,
                    optionPoolKey.strike,
                    priceAtExpiry,
                    ERC20(token1).decimals()
                ),
                1 ether
            );
        }
        // do transfer
        v3Pool.transferFromPool(token1, owner, amount);

        // setting user balance to zero
        usersBalances.updateOptionBalance(
            owner,
            optionPoolKey.hashOptionPool(),
            -usersBalances.getOptionBalance(
                owner,
                optionPoolKey.hashOptionPool()
            )
        );

        v3Pool.updatePoolBalances(
            optionPoolKey.hashOptionPool(),
            0,
            -int256(amount)
        );

        emit AlcorWithdraw(amount);
    }
}


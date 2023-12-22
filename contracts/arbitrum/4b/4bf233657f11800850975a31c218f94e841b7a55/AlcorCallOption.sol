// SPDX-License-Identifier: None
pragma solidity =0.8.12;

import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {TransferHelper} from "./TransferHelper.sol";

import {IAlcorOptionPoolFactory} from "./IAlcorOptionPoolFactory.sol";
import {IAlcorOptionPool} from "./IAlcorOptionPool.sol";

import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {SafeCast} from "./SafeCast.sol";

import {BaseOptionPool} from "./BaseOptionPool.sol";

import {AlcorUtils} from "./AlcorUtils.sol";

import {console} from "./console.sol";

contract AlcorCallOption is BaseOptionPool, IAlcorOptionPool {
    using FullMath for uint256;
    using FullMath for int256;
    using SafeCast for uint128;
    using SafeERC20 for ERC20;

    // errors
    error alreadyMinted();
    error notEntireBurn();

    // this variable is used to get the average underlying price
    uint32 SWAP_TWAP_DURATION = 65000;

    constructor() BaseOptionPool() {
        optionPoolInfo.isCall = true;
    }

    // @dev this function returns the hash which is used to find the LP position in mapping
    function getPositionKey(address owner, int24 tickLower, int24 tickUpper) public pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(owner, tickLower, tickUpper));
    }

    // @dev mints or burns user's entire position
    // @dev liquidity > 0 if mint position, liquidity < 0 otherwise
    function _modifyPosition(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity,
        int256 amount0Delta,
        int256 amount1Delta
    ) internal {
        if (liquidity == 0) revert ZeroLiquidity();

        // key of the LP position
        bytes32 positionKey = getPositionKey(owner, -tickUpper, -tickLower);

        // get the position
        LPPosition memory _position = LPpositionInfos[positionKey];

        // change deposit amounts
        // case of mint
        if (liquidity > 0) {
            LPpositionInfos[positionKey] = LPPosition({
                owner: owner,
                tickLower: -tickUpper,
                tickUpper: -tickLower,
                liquidity: uint128(liquidity),
                deposit_amount0: uint256(amount0Delta),
                deposit_amount1: uint256(amount1Delta),
                isOpen: true
            });
            addPos(owner, positionKey);
        }
        // case of burn
        else {
            // update user's options balance
            usersBalances[owner] += (-amount1Delta - int256(_position.deposit_amount1));

            // transfer dollarts to the owner
            ERC20(optionPoolInfo.token0).safeTransfer(owner, uint256(-amount0Delta));
            // transfer the collateral to the owner

            // case of bought call options
            if (_position.deposit_amount0 > uint256(-amount0Delta)) {
                // transfer only the collateral that was provided when position was minted
                ERC20(optionPoolInfo.token1).safeTransfer(owner, _position.deposit_amount1);
            }
            // case of sold call options
            else if (_position.deposit_amount0 <= uint256(-amount0Delta)) {
                // transfer all left collateral
                ERC20(optionPoolInfo.token1).safeTransfer(owner, uint256(-amount1Delta));
            }

            // clear the LP position
            delete LPpositionInfos[positionKey];
            removePos(owner, positionKey);
        }
    }

    // @dev this function allows to provide liquidity to the option pool
    // @param address of position owner
    // @param tickLower is the lower tick of option price range
    // @param tickUpper is the upper tick of option price range
    // @param amount is amount of liquidity in terms of uniswap v3
    function _mintLP(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) internal WhenNotExpired returns (uint256 amount0Delta, uint256 amount1Delta) {
        // mint the position interacting with conjugated uni v3 pool
        // amount0, amount1 are amounts deltas
        (amount0Delta, amount1Delta) = uniswapV3Pool.mint(owner, -tickUpper, -tickLower, amount, abi.encode());

        // key of the LP position
        bytes32 positionKey = getPositionKey(owner, -tickUpper, -tickLower);

        // get the position
        LPPosition memory _position = LPpositionInfos[positionKey];
        if (_position.liquidity > 0) revert alreadyMinted();

        _modifyPosition(owner, tickLower, tickUpper, int128(amount), int256(amount0Delta), int256(amount1Delta));

        console.log(amount0Delta, amount1Delta);
        // receive the funds from user
        ERC20(optionPoolInfo.token0).safeTransferFrom(owner, address(this), amount0Delta);
        ERC20(optionPoolInfo.token1).safeTransferFrom(owner, address(this), amount1Delta);

        emit AlcorMint(owner, amount0Delta, amount1Delta);
    }

    // @dev external mint function
    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override lock WhenNotExpired returns (uint256 amount0Delta, uint256 amount1Delta) {
        (amount0Delta, amount1Delta) = _mintLP(msg.sender, tickLower, tickUpper, amount);
    }

    // @dev this function burns the option LP position
    // @dev we don't need whenNotExpired modifier here as user should be able to burn at any time
    // @param address of position owner
    // @param tickLower is the lower tick of option price range
    // @param tickUpper is the upper tick of option price range
    // @param amount is amount of liquidity in terms of uniswap v3
    function _burnLP(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) internal returns (uint256 amount0Delta, uint256 amount1Delta) {
        // key of the LP position
        bytes32 positionKey = getPositionKey(owner, -tickUpper, -tickLower);

        // get the position
        LPPosition memory _position = LPpositionInfos[positionKey];

        if (_position.liquidity != amount) revert notEntireBurn();

        (amount0Delta, amount1Delta) = uniswapV3Pool.burn(owner, -tickUpper, -tickLower, amount);

        _modifyPosition(owner, tickLower, tickUpper, -int128(amount), -int256(amount0Delta), -int256(amount1Delta));

        emit AlcorBurn(owner, amount0Delta, amount1Delta);
    }

    // @dev external burn function
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override lock returns (uint256 amount0Delta, uint256 amount1Delta) {
        (amount0Delta, amount1Delta) = _burnLP(msg.sender, tickLower, tickUpper, amount);
    }

    // @dev this function allows to update the position, i.e. to change provided amount of liquidity
    function updatePosition(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external lock WhenNotExpired returns (uint256 amount0Delta, uint256 amount1Delta) {
        // key of the LP position
        bytes32 positionKey = getPositionKey(msg.sender, -tickUpper, -tickLower);
        // get the position previous liquidity
        uint128 positionLiquidity = LPpositionInfos[positionKey].liquidity;

        // burn position if there was any
        if (positionLiquidity > 0) {
            _burnLP(msg.sender, tickLower, tickUpper, positionLiquidity);
        }
        // mint new position with liquidity
        (amount0Delta, amount1Delta) = _mintLP(msg.sender, tickLower, tickUpper, amount);

        emit AlcorUpdatePosition(msg.sender, tickLower, tickUpper, amount);
    }

    // @dev this function allows to collect the spread fees accrued by user's LP position
    // @dev we don't need whenNotExpired modifier here as user should be able to collect fees at any time
    function collectFees(
        int24 tickLower,
        int24 tickUpper
    ) external override returns (uint128 amount0, uint128 amount1) {
        // first off, we update fees growth inside the position
        uniswapV3Pool.burn(msg.sender, -tickUpper, -tickLower, 0);

        // collect fees
        (amount0, amount1) = uniswapV3Pool.collect(
            msg.sender,
            -tickUpper,
            -tickLower,
            type(uint128).max,
            type(uint128).max
        );

        // do transfers
        ERC20(optionPoolInfo.token0).safeTransfer(msg.sender, amount0);
        ERC20(optionPoolInfo.token1).safeTransfer(msg.sender, amount1);

        emit AlcorCollect(msg.sender, amount0, amount1);
    }

    function swap(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public lock WhenNotExpired returns (int256 amount0, int256 amount1) {
        int24 twapTickUnderlyingPair = AlcorUtils.getTwap(realUniswapV3Pool, SWAP_TWAP_DURATION);

        (amount0, amount1) = uniswapV3Pool.swap(
            // @dev address(0) doesn't mean anything - it's unused variable
            address(0),
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            twapTickUnderlyingPair
        );

        console.log('swap: amount0, amount1');
        console.logInt(amount0);
        console.logInt(amount1);

        // do the transfers and collect payment
        if (zeroForOne) {
            // transfer token1
            if (amount1 < 0) ERC20(optionPoolInfo.token1).safeTransfer(msg.sender, uint256(-amount1));
            // receive token0
            ERC20(optionPoolInfo.token0).safeTransferFrom(msg.sender, address(this), uint256(amount0));
        } else {
            // transfer token0
            if (amount0 < 0) ERC20(optionPoolInfo.token0).safeTransfer(msg.sender, uint256(-amount0));
            // receive token1
            ERC20(optionPoolInfo.token1).safeTransferFrom(msg.sender, address(this), uint256(amount1));
        }
        // update option balance
        // we subtract because this AMM's virtual balance change
        usersBalances[msg.sender] -= amount1;

        emit AlcorSwap(msg.sender, amount0, amount1);
    }

    // @dev this function allows to either exercise a call option or withdraw a collateral
    function withdraw() external lock returns (uint256 amount) {
        if (!isExpired) revert notYetExpired();

        int256 userOptionBalance = usersBalances[msg.sender];
        if (userOptionBalance == 0) revert zeroOptionBalance();

        // case of sold call options
        if (userOptionBalance < 0) {
            amount = uint256(-userOptionBalance).mulDiv(
                AlcorUtils.getPayoffCoefficient(
                    AlcorUtils.GetPayoffCoefficientInput({isLong: false, payoffCoefficient: payoffCoefficient})
                ),
                1 ether
            );
        }
        // case of bought call options
        else {
            amount = uint256(userOptionBalance).mulDiv(
                AlcorUtils.getPayoffCoefficient(
                    AlcorUtils.GetPayoffCoefficientInput({isLong: true, payoffCoefficient: payoffCoefficient})
                ),
                1 ether
            );
        }

        // update the balance
        usersBalances[msg.sender] = 0;
        // do transfer
        ERC20(optionPoolInfo.token1).safeTransfer(msg.sender, amount);

        emit AlcorWithdraw(amount);
    }
}

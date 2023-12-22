// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import { Factory } from "./Factory.sol";
import { Lendgine } from "./Lendgine.sol";
import { Pair } from "./Pair.sol";
import { IMintCallback } from "./IMintCallback.sol";
import { PRBMathUD60x18 } from "./PRBMathUD60x18.sol";
import { PRBMath } from "./PRBMath.sol";

import { CallbackValidation } from "./CallbackValidation.sol";
import { SafeTransferLib } from "./libraries_SafeTransferLib.sol";
import { LendgineAddress } from "./LendgineAddress.sol";
import { IUniswapV2Factory } from "./IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "./IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "./IUniswapV2Callee.sol";
import { Payment } from "./Payment.sol";
import { Multicall } from "./Multicall.sol";

/// @notice Facilitates mint and burning Numoen Positions
/// @author Kyle Scott (https://github.com/numoen/manager/blob/master/src/LendgineRouter.sol)
contract LendgineRouter is Multicall, Payment, IMintCallback, IUniswapV2Callee {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Mint(address indexed recipient, address indexed lendgine, uint256 shares, uint256 liquidity);

    event Burn(address indexed payer, address indexed lendgine, uint256 shares, uint256 liquidity);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error LivelinessError();

    error SlippageError();

    error UnauthorizedError();

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable factory;

    address public immutable uniFactory;

    /*//////////////////////////////////////////////////////////////
                           LIVELINESS MODIFIER
    //////////////////////////////////////////////////////////////*/

    modifier checkDeadline(uint256 deadline) {
        if (deadline < block.timestamp) revert LivelinessError();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _factory,
        address _uniFactory,
        address _weth
    ) Payment(_weth) {
        factory = _factory;
        uniFactory = _uniFactory;
    }

    /*//////////////////////////////////////////////////////////////
                            CALLBACK LOGIC
    //////////////////////////////////////////////////////////////*/

    struct CallbackData {
        LendgineAddress.LendgineKey key;
        address uniPair;
        uint256 userAmount;
        address payer;
    }

    function MintCallback(uint256 amountS, bytes calldata data) external override {
        CallbackData memory decoded = abi.decode(data, (CallbackData));
        CallbackValidation.verifyCallback(factory, decoded.key);

        uint256 liquidity = Lendgine(msg.sender).convertAssetToLiquidity(amountS);

        (uint256 amountBOut, uint256 amountSOut) = Pair(Lendgine(msg.sender).pair()).burn(address(this), liquidity);
        SafeTransferLib.safeTransfer(decoded.key.base, decoded.uniPair, amountBOut);

        uint256 sOut = getSOut(amountBOut, decoded.uniPair, decoded.key.base < decoded.key.speculative);
        IUniswapV2Pair(decoded.uniPair).swap(
            decoded.key.base < decoded.key.speculative ? 0 : sOut,
            decoded.key.base < decoded.key.speculative ? sOut : 0,
            msg.sender,
            bytes("")
        );

        SafeTransferLib.safeTransfer(decoded.key.speculative, msg.sender, amountSOut);
        if (amountS - sOut - amountSOut > decoded.userAmount) revert SlippageError();
        pay(decoded.key.speculative, decoded.payer, msg.sender, amountS - sOut - amountSOut);
    }

    struct UniCallbackData {
        address lendgine;
        address pair;
        address speculative;
        address base;
        uint256 liquidity;
        uint256 repayAmount;
        address recipient;
    }

    function uniswapV2Call(
        address,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        UniCallbackData memory decoded = abi.decode(data, (UniCallbackData));

        SafeTransferLib.safeTransfer(
            decoded.base,
            decoded.pair,
            decoded.base < decoded.speculative ? amount0 : amount1
        );
        SafeTransferLib.safeTransfer(
            decoded.speculative,
            decoded.pair,
            decoded.base < decoded.speculative ? amount1 : amount0
        );

        Pair(decoded.pair).mint(decoded.liquidity);
        uint256 amountSUnlocked = Lendgine(decoded.lendgine).burn(address(this));

        SafeTransferLib.safeTransfer(decoded.speculative, msg.sender, decoded.repayAmount);
        if (decoded.recipient != address(this))
            SafeTransferLib.safeTransfer(decoded.speculative, decoded.recipient, amountSUnlocked - decoded.repayAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 LOGIC
    //////////////////////////////////////////////////////////////*/

    struct MintParams {
        address base;
        address speculative;
        uint256 baseScaleFactor;
        uint256 speculativeScaleFactor;
        uint256 upperBound;
        uint256 liquidity;
        uint256 borrowAmount;
        uint256 sharesMin;
        address recipient;
        uint256 deadline;
    }

    /// @notice Mints an option using a flash loan and swapping through an external liquidity pool
    function mint(MintParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (address lendgine, uint256 shares)
    {
        LendgineAddress.LendgineKey memory lendgineKey = LendgineAddress.LendgineKey({
            base: params.base,
            speculative: params.speculative,
            baseScaleFactor: params.baseScaleFactor,
            speculativeScaleFactor: params.speculativeScaleFactor,
            upperBound: params.upperBound
        });

        lendgine = LendgineAddress.computeLendgineAddress(
            factory,
            params.base,
            params.speculative,
            params.baseScaleFactor,
            params.speculativeScaleFactor,
            params.upperBound
        );

        address uniPair = IUniswapV2Factory(uniFactory).getPair(params.base, params.speculative);
        uint256 speculativeAmount = Lendgine(lendgine).convertLiquidityToAsset(params.liquidity);

        shares = Lendgine(lendgine).mint(
            params.recipient,
            speculativeAmount + params.borrowAmount,
            abi.encode(
                CallbackData({ key: lendgineKey, uniPair: uniPair, userAmount: speculativeAmount, payer: msg.sender })
            )
        );

        if (shares < params.sharesMin) revert SlippageError();
        emit Mint(params.recipient, lendgine, shares, params.liquidity);
    }

    struct BurnParams {
        address base;
        address speculative;
        uint256 baseScaleFactor;
        uint256 speculativeScaleFactor;
        uint256 upperBound;
        uint256 sharesMax;
        uint256 liquidity;
        address recipient;
        uint256 deadline;
    }

    /// @notice Burns an option position by borrowing funds, paying back liquidity and unlocking collateral
    function burn(BurnParams calldata params)
        external
        payable
        checkDeadline(params.deadline)
        returns (address lendgine)
    {
        lendgine = LendgineAddress.computeLendgineAddress(
            factory,
            params.base,
            params.speculative,
            params.baseScaleFactor,
            params.speculativeScaleFactor,
            params.upperBound
        );
        address pair = LendgineAddress.computePairAddress(
            factory,
            params.base,
            params.speculative,
            params.baseScaleFactor,
            params.speculativeScaleFactor,
            params.upperBound
        );

        Lendgine(lendgine).accrueInterest();
        uint256 shares = Lendgine(lendgine).convertLiquidityToShare(params.liquidity);
        if (shares > params.sharesMax) revert SlippageError();

        uint256 r0;
        uint256 r1;
        {
            (uint256 p0, uint256 p1) = (Pair(pair).reserve0(), Pair(pair).reserve1());
            uint256 _totalSupply = Pair(pair).totalSupply();

            r0 = PRBMath.mulDiv(p0, params.liquidity, _totalSupply);
            r1 = PRBMath.mulDiv(p1, params.liquidity, _totalSupply);
        }

        address uniPair = IUniswapV2Factory(uniFactory).getPair(params.base, params.speculative);
        uint256 repayAmount;
        {
            (uint256 u0, uint256 u1, ) = IUniswapV2Pair(uniPair).getReserves();
            repayAmount = determineRepayAmount(
                RepayParams({
                    r0: r0,
                    r1: r1,
                    u0: params.base < params.speculative ? u0 : u1,
                    u1: params.base < params.speculative ? u1 : u0
                })
            );
        }

        Lendgine(lendgine).transferFrom(msg.sender, lendgine, shares);
        IUniswapV2Pair(uniPair).swap(
            params.base < params.speculative ? r0 : r1,
            params.base < params.speculative ? r1 : r0,
            address(this),
            abi.encode(
                UniCallbackData({
                    lendgine: lendgine,
                    pair: pair,
                    speculative: params.speculative,
                    base: params.base,
                    liquidity: params.liquidity,
                    repayAmount: repayAmount,
                    recipient: params.recipient
                })
            )
        );

        emit Burn(msg.sender, lendgine, shares, params.liquidity);
    }

    struct SkimParams {
        address base;
        address speculative;
        uint256 baseScaleFactor;
        uint256 speculativeScaleFactor;
        uint256 upperBound;
        address recipient;
    }

    /// @notice Collects any funds that have been donated to the corresponding pair contract
    function skim(SkimParams calldata params) external payable {
        address pair = LendgineAddress.computePairAddress(
            factory,
            params.base,
            params.speculative,
            params.baseScaleFactor,
            params.speculativeScaleFactor,
            params.upperBound
        );

        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        Pair(pair).skim(recipient);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    struct RepayParams {
        uint256 r0;
        uint256 r1;
        uint256 u0;
        uint256 u1;
    }

    function determineRepayAmount(RepayParams memory params) internal pure returns (uint256) {
        uint256 a = params.u0 * params.u1 * 1000;
        uint256 b = params.u0 - params.r0;
        uint256 c = 1000 * params.r1;
        uint256 d = 1000 * params.u1;

        return (((a / b) + c - d) / 997) + 1;
    }

    function getSOut(
        uint256 amountBIn,
        address uniPair,
        bool isBase0
    ) internal view returns (uint256) {
        (uint256 u0, uint256 u1, ) = IUniswapV2Pair(uniPair).getReserves();
        uint256 reserveIn = isBase0 ? u0 : u1;
        uint256 reserveOut = isBase0 ? u1 : u0;

        uint256 amountInWithFee = amountBIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }
}


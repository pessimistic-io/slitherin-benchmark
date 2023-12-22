// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Owned} from "./Owned.sol";
import {IV3SwapRouter} from "./IV3SwapRouter.sol";
import {ICamelotRouter} from "./ICamelotRouter.sol";
import {ICamelotPair} from "./ICamelotPair.sol";
import {IPirexGmx} from "./IPirexGmx.sol";
import {PxERC20} from "./PxERC20.sol";

contract PirexGmxDepositRouter is Owned, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    IV3SwapRouter public constant UNISWAP_ROUTER =
        IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    ICamelotRouter public constant CAMELOT_ROUTER =
        ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    ERC20 public constant GMX =
        ERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    IPirexGmx public immutable PIREX_GMX;
    PxERC20 public immutable PXGMX;

    // Camelot referral for fee sharing
    address public camelotReferral;
    // Uniswap pool fee
    uint24 public poolFee = 3_000;

    event CamelotReferralUpdated(address camelotReferral);
    event PoolFeeUpdated(uint24 _poolFee);
    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 deposited,
        uint256 postFeeAmount,
        uint256 feeAmount
    );

    error ZeroAddress();
    error ZeroAmount();

    /**
        @param  _camelotReferral   address  Camelot referral address
        @param  _pirexGmxPlatform  address  Platform address (e.g. PirexGmx)
     */
    constructor(
        address _camelotReferral,
        address _pirexGmxPlatform
    ) Owned(msg.sender) {
        if (_pirexGmxPlatform == address(0)) revert ZeroAddress();

        PIREX_GMX = IPirexGmx(_pirexGmxPlatform);
        PXGMX = IPirexGmx(_pirexGmxPlatform).pxGmx();

        GMX.safeApprove(_pirexGmxPlatform, type(uint256).max);
        GMX.safeApprove(address(UNISWAP_ROUTER), type(uint256).max);
        WETH.safeApprove(address(CAMELOT_ROUTER), type(uint256).max);

        // Referral can be zero-address
        camelotReferral = _camelotReferral;
    }

    /**
     * @notice Set the address of the Camelot referral
     * @param  _camelotReferral  address  Referral address
     */
    function setCamelotReferral(address _camelotReferral) external onlyOwner {
        camelotReferral = _camelotReferral;

        emit CamelotReferralUpdated(_camelotReferral);
    }

    /**
        @notice Set the Uniswap pool fee
        @param  _poolFee  uint24  Uniswap pool fee
     */
    function setPoolFee(uint24 _poolFee) external onlyOwner {
        if (_poolFee == 0) revert ZeroAmount();

        poolFee = _poolFee;

        emit PoolFeeUpdated(_poolFee);
    }

    /**
     * @notice Deposit GMX for pxGMX
     * @dev    Try to swap GMX for WETH on UniswapV3, then swap WETH for pxGMX on Camelot
     *         If unsuccessful deposit GMX for pxGMX on PirexGmx
     * @param  amount     uint256  GMX amount
     * @param  receiver   address  pxGMX receiver
     * @return amountOut  uint256  pxGMX minted for the receiver
     * @return feeAmount  uint256  pxGMX distributed as fees
     */
    function depositGmx(uint256 amount, address receiver)
        external
        nonReentrant
        returns (uint256 amountOut, uint256 feeAmount)
    {
        // Calculate pxGMX amount received after fees from depositing directly through PirexGmx
        uint256 minPxGmxAmount = amount
            * (1_000_000 - PIREX_GMX.fees(IPirexGmx.Fees.Deposit)) / (1_000_000);

        // Calculate min WETH amount required to get minPxGmxAmount on WETH/pxGMX Camelot pool
        uint256 minWethAmount = _getAmountIn(minPxGmxAmount);

        // Transfer GMX from sender
        GMX.safeTransferFrom(msg.sender, address(this), amount);

        // Try to swap GMX for at least minWethAmount on UniswapV3
        try UNISWAP_ROUTER.exactInputSingle(
            _getExactInputSingleParams(amount, minWethAmount)
        ) returns (uint256 receivedWethAmount) {
            // If successful swap receivedWethAmount for pxGMX on Camelot
            address[] memory path = new address[](2);
            path[0] = address(WETH);
            path[1] = address(PXGMX);

            uint256 pxGmxBalanceBefore = PXGMX.balanceOf(receiver);

            CAMELOT_ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                receivedWethAmount,
                minPxGmxAmount,
                path,
                receiver,
                camelotReferral,
                type(uint256).max
            );

            amountOut = PXGMX.balanceOf(receiver) - pxGmxBalanceBefore;
            feeAmount = uint256(0);
        } catch {
            // If unsuccessful deposit GMX for pxGMX on PirexGmx
            (amountOut, feeAmount) = PIREX_GMX.depositGmx(amount, receiver);
        }

        emit DepositGmx(msg.sender, receiver, amount, amountOut, feeAmount);
    }

    /**
     * @notice Calculate WETH amount required for a given pxGMX amount in the WETH/pxGMX Camelot pool
     * @dev    based on UniswapV2Library.getAmountIn
     * @param  amountOut  uint256  pxGMX amount
     * @return            uint256  Amount In
     */
    function _getAmountIn(uint256 amountOut) private view returns (uint256) {
        address pair = CAMELOT_ROUTER.getPair(address(WETH), address(PXGMX));
        (uint112 reserveIn, uint112 reserveOut,,) = ICamelotPair(pair).getReserves();

        if (amountOut >= reserveOut) return type(uint256).max;

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        uint256 amountIn = (numerator / denominator) + 1;

        return amountIn;
    }

    /**
     * @notice Constructs ExactInputSingleParams with constant field values pre-defined (e.g. recipient)
     * @param  amountIn           uint256                               Input token amount
     * @param  amountOutMinimum   uint256                               Minimum output token amount
     * @return                    IV3SwapRouter.ExactInputSingleParams  Input params
     */
    function _getExactInputSingleParams(
        uint256 amountIn,
        uint256 amountOutMinimum
    ) private view returns (IV3SwapRouter.ExactInputSingleParams memory) {
        return IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(GMX),
            tokenOut: address(WETH),
            fee: poolFee,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: uint160(0)
        });
    }
}


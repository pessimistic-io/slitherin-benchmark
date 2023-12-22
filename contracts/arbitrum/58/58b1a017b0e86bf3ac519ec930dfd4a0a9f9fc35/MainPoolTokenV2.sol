// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./IMainPoolToken.sol";
import "./IRouter.sol";
import "./DexLibrary.sol";


contract MainPoolTokenV2 is IMainPoolToken {
    using SafeERC20 for IERC20;

    uint256 constant public DIVIDER = 10000;
    uint256 constant public MAX_SWAP_FEE = 300;

    IERC20 public stable;
    IERC20 public token;

    IRouter public router;
    address public factory;
    uint256 public swapFee;

    uint256 public numberOfSwaps;
    address[] public swapPathTokenToStable;
    address[] public swapPathStableToToken;

    error MainPoolTokenV2InvalidAddress(address account);
    error MainPoolTokenV2WrongParameters();
    error MainPoolTokenV2InvalidSwapFee(uint256 amount);
    error MainPoolTokenV2InvalidSwapPath();
    error MainPoolTokenV2InsufficientInputAmount(uint256 amount);
    error MainPoolTokenV2InsufficientLiquidity();

    constructor (
        address _token,
        address _stable,
        address _router,
        uint256 _swapFee,
        address[] memory _swapPathStableToToken
    ) {
        if (_token == address(0) || _stable == address(0) || _router == address(0)) {
            revert MainPoolTokenV2InvalidAddress(address(0));
        }
        if (_swapFee > MAX_SWAP_FEE) {
            revert MainPoolTokenV2InvalidSwapFee(_swapFee);
        }
        if (_swapPathStableToToken[0] != _stable || _swapPathStableToToken[_swapPathStableToToken.length - 1] != _token) {
            revert MainPoolTokenV2InvalidSwapPath();
        }
        token = IERC20(_token);
        stable = IERC20(_stable);
        router = IRouter(_router);
        factory = router.factory();
        swapFee = _swapFee;
        swapPathStableToToken = _swapPathStableToToken;
        numberOfSwaps = _swapPathStableToToken.length - 1;
        for (uint256 i; i <= numberOfSwaps;) {
            swapPathTokenToStable.push(_swapPathStableToToken[numberOfSwaps - i]);
            unchecked {
                ++i;
            }
        }
    }

    function swapTokenToStable(uint256 tokenAmount, address to) external override returns (uint256 stableAmountOut) {
        if (tokenAmount == 0) return tokenAmount;
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        uint256 outputStableBalanceBefore = stable.balanceOf(to);
        token.approve(address(router), tokenAmount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            1,
            swapPathTokenToStable,
            to,
            block.timestamp
        );
        stableAmountOut = stable.balanceOf(to) - outputStableBalanceBefore;

    }

    function swapStableToToken(uint256 stableAmount, address to) external override returns (uint256 tokenAmountOut) {
        if (stableAmount == 0) return stableAmount;
        stable.safeTransferFrom(msg.sender, address(this), stableAmount);
        uint256 outputTokenBalanceBefore = token.balanceOf(to);
        stable.approve(address(router), stableAmount);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            stableAmount,
            1,
            swapPathStableToToken,
            to,
            block.timestamp
        );
        tokenAmountOut = token.balanceOf(to) - outputTokenBalanceBefore;
    }

    function applyCoeffCorrectionToSell(
        uint256 stableAmount
    ) external view override returns (uint256 stableAmountWithCorrection) {
        return stableAmount * DIVIDER ** numberOfSwaps /
            (DIVIDER ** numberOfSwaps / 2  + (DIVIDER - swapFee) ** numberOfSwaps/ 2);
    }

    function getAmountOutTokenToStable(uint256 tokenAmount) external view override returns (uint256 stableAmount) {
        if (tokenAmount == 0) return 0;
        address[] memory path = swapPathTokenToStable;
        uint256[] memory amounts = new uint256[](path.length);
        amounts[0] = tokenAmount;
        uint256 len = path.length;
        for (uint256 i; i < len - 1;) {
            (uint256 reserveIn, uint256 reserveOut) = DexLibrary.getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
            unchecked {
                ++i;
            }
        }
        stableAmount = amounts[amounts.length - 1];
    }

    function getAmountOutStableToToken(uint256 stableAmount) external view override returns (uint256 tokenAmount) {
        if (stableAmount == 0) return 0;
        address[] memory path = swapPathStableToToken;
        uint256[] memory amounts = new uint256[](path.length);
        amounts[0] = stableAmount;
        uint256 len = path.length;
        for (uint256 i; i < len - 1;) {
            (uint256 reserveIn, uint256 reserveOut) = DexLibrary.getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
            unchecked {
                ++i;
            }
        }
        tokenAmount = amounts[amounts.length - 1];
    }

    function _getAmountOut(
        uint256 amountIn_,
        uint256 reserveIn_,
        uint256 reserveOut_
    ) private pure returns (uint256 amountOut) {
        if (amountIn_ == 0) {
            revert MainPoolTokenV2InsufficientInputAmount(0);
        }
        if (reserveIn_ == 0 || reserveOut_ == 0) {
            revert MainPoolTokenV2InsufficientLiquidity();
        }
        uint256 numerator = amountIn_ * reserveOut_;
        uint256 denominator = reserveIn_ + amountIn_;
        amountOut = numerator / denominator;
    }
}


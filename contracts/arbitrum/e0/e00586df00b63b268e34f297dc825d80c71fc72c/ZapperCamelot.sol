//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Zapper.sol";
import "./ICamelotRouter.sol";
import "./ICamelotPair.sol";
import "./IWETH.sol";

//import 'hardhat/console.sol';

contract ZapperCamelot is Zapper {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal constant CAMELOT_ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant TREASURY = 0xEaD9f532C72CF35dAb18A42223eE7A1B19bC5aBF;

    constructor() {
        WFTM = WETH;
        _setDefaultRouter(CAMELOT_ROUTER);

        address _LDO = 0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60;
        address _USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        address _SPA = 0x5575552988A3A80504bBaeB1311674fCFd40aD4B;

        address[] memory _wethToLdo = new address[](3);
        _wethToLdo[0] = WETH;
        _wethToLdo[1] = _USDC;
        _wethToLdo[2] = _LDO;

        _setSwapPath(WETH, _LDO, CAMELOT_ROUTER, _wethToLdo);

        address _GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
        address[] memory _wethToGmx = new address[](3);
        _wethToGmx[0] = WETH;
        _wethToGmx[1] = _USDC;
        _wethToGmx[2] = _GMX;

        _setSwapPath(WETH, _GMX, CAMELOT_ROUTER, _wethToGmx);

        address _USDs = 0xD74f5255D557944cf7Dd0E45FF521520002D5748;
        address[] memory _wethToUsds = new address[](3);
        _wethToUsds[0] = WETH;
        _wethToUsds[1] = _USDC;
        _wethToUsds[2] = _USDs;

        _setSwapPath(WETH, _USDs, CAMELOT_ROUTER, _wethToUsds);

        address _MIM = 0xFEa7a6a0B346362BF88A9e4A88416B77a57D6c2A;
        address[] memory _wethToMim = new address[](3);
        _wethToMim[0] = WETH;
        _wethToMim[1] = _USDC;
        _wethToMim[2] = _MIM;

        _setSwapPath(WETH, _MIM, CAMELOT_ROUTER, _wethToMim);

        address[] memory _wethToSpa = new address[](4);
        _wethToSpa[0] = WETH;
        _wethToSpa[1] = _USDC;
        _wethToSpa[2] = _USDs;
        _wethToSpa[3] = _SPA;

        _setSwapPath(WETH, _SPA, CAMELOT_ROUTER, _wethToSpa);
    }

    function _getRouter(
        address /* _lpToken */
    ) internal view override returns (address) {
        return CAMELOT_ROUTER;
    }

    function _swap(
        address _fromToken,
        address _toToken,
        uint256 _amount
    ) internal override returns (uint256 _toTokenAmount) {
        if (_fromToken == _toToken) return _amount;
        SwapPath memory _swapPath = getSwapPath(_fromToken, _toToken);

        IERC20(_fromToken).safeApprove(_swapPath.unirouter, 0);
        IERC20(_fromToken).safeApprove(_swapPath.unirouter, type(uint256).max);

        //debugging: uncomment this block

        // console.log('_inputAmount', _amount);
        // console.log('_fromToken:', IERC20Metadata(_fromToken).symbol());
        // console.log('_toToken:', IERC20Metadata(_toToken).symbol());
        // console.log('_path:');
        // for (uint256 i; i < _swapPath.path.length - 1; i++) {
        //     console.log(IERC20Metadata(_swapPath.path[i]).symbol());
        // }
        // console.log(_swapPath.path[_swapPath.path.length - 1]);

        // console.log(IERC20Metadata(_swapPath.path[_swapPath.path.length - 1]).symbol());

        uint256 _toTokenBefore = IERC20(_toToken).balanceOf(address(this));
        ICamelotRouter(_swapPath.unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(_amount, 0, _swapPath.path, address(this), TREASURY, block.timestamp);

        _toTokenAmount = IERC20(_toToken).balanceOf(address(this)) - _toTokenBefore;

        //console.log("_toTokenAmount:", _toTokenAmount);
    }

    function _addLiquidity(
        address _router,
        address _token0,
        address _token1,
        uint256 _token0Out,
        uint256 _token1Out
    ) internal {
        ICamelotRouter(_router).addLiquidity(_token0, _token1, _token0Out, _token1Out, 0, 0, address(this), block.timestamp);
    }

    function _removeLiquidity(
        address _router,
        address _token0,
        address _token1,
        uint256 _amountLpIn
    ) internal {
        ICamelotRouter(_router).removeLiquidity(_token0, _token1, _amountLpIn, 0, 0, address(this), block.timestamp);
    }

    function _unzapFromLp(
        address _fromLpToken,
        address _toToken,
        uint256 _amountLpIn,
        uint256 _minAmountOut
    ) internal override returns (uint256 _amountOut) {
        address _router = _getRouter(_fromLpToken);

        address _token0 = ICamelotPair(_fromLpToken).token0();
        address _token1 = ICamelotPair(_fromLpToken).token1();

        IERC20(_fromLpToken).safeApprove(_router, 0);
        IERC20(_fromLpToken).safeApprove(_router, _amountLpIn);

        _removeLiquidity(_router, _token0, _token1, _amountLpIn);

        address _defaultRouter = unirouter;
        unirouter = _router;
        // Uses lpToken' _router as the default router
        // You can override this by using setting a custom path
        // Using setSwapPath

        _swap(_token0, _toToken, IERC20(_token0).balanceOf(address(this)));
        _swap(_token1, _toToken, IERC20(_token1).balanceOf(address(this)));

        // Revert back to defaultRouter for swaps
        unirouter = _defaultRouter;

        _amountOut = IERC20(_toToken).balanceOf(address(this));

        require(_amountOut >= _minAmountOut, 'slippage-rekt-you');

        if (_toToken == WETH) {
            IWETH(WETH).withdraw(_amountOut);

            (bool _success, ) = msg.sender.call{ value: _amountOut }('');
            require(_success, 'eth-transfer-failed');
        } else {
            IERC20(_toToken).transfer(msg.sender, _amountOut);
        }
    }

    function _getRatio(address _lpToken) internal view returns (uint256) {
        address _token0 = ICamelotPair(_lpToken).token0();
        address _token1 = ICamelotPair(_lpToken).token1();

        (uint256 opLp0, uint256 opLp1, , ) = ICamelotPair(_lpToken).getReserves();
        uint256 lp0Amt = (opLp0 * (10**18)) / (10**IERC20Metadata(_token0).decimals());
        uint256 lp1Amt = (opLp1 * (10**18)) / (10**IERC20Metadata(_token1).decimals());
        uint256 totalSupply = lp0Amt + (lp1Amt);
        return (lp0Amt * (10**18)) / (totalSupply);
    }

    function _zapToLp(
        address _fromToken,
        address _toLpToken,
        uint256 _amountIn,
        uint256 _minLpAmountOut
    ) internal override returns (uint256 _lpAmountOut) {
        if (msg.value > 0) {
            // If you send FTM instead of WETH these requirements must hold.
            require(_fromToken == WETH, 'invalid-from-token');
            require(_amountIn == msg.value, 'invalid-amount-in');
            // Auto-wrap FTM to WETH
            IWETH(WETH).deposit{ value: msg.value }();
        } else {
            IERC20(_fromToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        }

        address _router = _getRouter(_toLpToken);

        IERC20(_fromToken).safeApprove(_router, 0);
        IERC20(_fromToken).safeApprove(_router, _amountIn);

        address _token0 = ICamelotPair(_toLpToken).token0();
        address _token1 = ICamelotPair(_toLpToken).token1();

        address _defaultRouter = unirouter;
        unirouter = _router;
        // Uses lpToken' _router as the default router
        // You can override this by using setting a custom path
        // Using setSwapPath

        uint256 _token0Out;
        uint256 _token1Out;

        uint256 _amount0In = (_amountIn * _getRatio(_toLpToken)) / 10**18;
        uint256 _amount1In = _amountIn - _amount0In;
        _token0Out = _swap(_fromToken, _token0, _amount0In);
        _token1Out = _swap(_fromToken, _token1, _amount1In);

        // Revert back to defaultRouter for swaps
        unirouter = _defaultRouter;

        IERC20(_token0).safeApprove(_router, 0);
        IERC20(_token1).safeApprove(_router, 0);
        IERC20(_token0).safeApprove(_router, _token0Out);
        IERC20(_token1).safeApprove(_router, _token1Out);

        uint256 _lpBalanceBefore = IERC20(_toLpToken).balanceOf(address(this));

        _addLiquidity(_router, _token0, _token1, _token0Out, _token1Out);

        _lpAmountOut = IERC20(_toLpToken).balanceOf(address(this)) - _lpBalanceBefore;
        require(_lpAmountOut >= _minLpAmountOut, 'slippage-rekt-you');
    }
}


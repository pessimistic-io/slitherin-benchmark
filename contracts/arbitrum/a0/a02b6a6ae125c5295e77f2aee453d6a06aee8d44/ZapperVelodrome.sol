//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ZapperOptimism.sol";
import "./IVelodromeRouter.sol";
//import "hardhat/console.sol";

contract ZapperVelodrome is ZapperOptimism {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    /// @notice ZIPSWAP ROUTER AS DEFAULT FOR LP TOKENS AND SWAPS

    address internal constant VELODROME_ROUTER =
        0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9;

    constructor() {
        _setDefaultRouter(VELODROME_ROUTER);

        address[] memory _path = new address[](3);
        _path[0] = 0x4200000000000000000000000000000000000006;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0xdFA46478F9e5EA86d57387849598dbFB2e964b02;
        _setSwapPath(
            0x4200000000000000000000000000000000000006,
            0xdFA46478F9e5EA86d57387849598dbFB2e964b02,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x4200000000000000000000000000000000000006;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x217D47011b23BB961eB6D93cA9945B7501a5BB11;
        _setSwapPath(
            0x4200000000000000000000000000000000000006,
            0x217D47011b23BB961eB6D93cA9945B7501a5BB11,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x4200000000000000000000000000000000000006;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0xc40F949F8a4e094D1b49a23ea9241D289B7b2819;
        _setSwapPath(
            0x4200000000000000000000000000000000000006,
            0xc40F949F8a4e094D1b49a23ea9241D289B7b2819,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x4200000000000000000000000000000000000006;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
        _setSwapPath(
            0x4200000000000000000000000000000000000006,
            0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x4200000000000000000000000000000000000006;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x2E3D870790dC77A83DD1d18184Acc7439A53f475;
        _setSwapPath(
            0x4200000000000000000000000000000000000006,
            0x2E3D870790dC77A83DD1d18184Acc7439A53f475,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x4200000000000000000000000000000000000006;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x10010078a54396F62c96dF8532dc2B4847d47ED3;
        _setSwapPath(
            0x4200000000000000000000000000000000000006,
            0x10010078a54396F62c96dF8532dc2B4847d47ED3,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0xdFA46478F9e5EA86d57387849598dbFB2e964b02;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x4200000000000000000000000000000000000006;
        _setSwapPath(
            0xdFA46478F9e5EA86d57387849598dbFB2e964b02,
            0x4200000000000000000000000000000000000006,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x217D47011b23BB961eB6D93cA9945B7501a5BB11;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x4200000000000000000000000000000000000006;
        _setSwapPath(
            0x217D47011b23BB961eB6D93cA9945B7501a5BB11,
            0x4200000000000000000000000000000000000006,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0xc40F949F8a4e094D1b49a23ea9241D289B7b2819;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x4200000000000000000000000000000000000006;
        _setSwapPath(
            0xc40F949F8a4e094D1b49a23ea9241D289B7b2819,
            0x4200000000000000000000000000000000000006,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x4200000000000000000000000000000000000006;
        _setSwapPath(
            0xCB8FA9a76b8e203D8C3797bF438d8FB81Ea3326A,
            0x4200000000000000000000000000000000000006,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x2E3D870790dC77A83DD1d18184Acc7439A53f475;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x4200000000000000000000000000000000000006;
        _setSwapPath(
            0x2E3D870790dC77A83DD1d18184Acc7439A53f475,
            0x4200000000000000000000000000000000000006,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x10010078a54396F62c96dF8532dc2B4847d47ED3;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x4200000000000000000000000000000000000006;
        _setSwapPath(
            0x10010078a54396F62c96dF8532dc2B4847d47ED3,
            0x4200000000000000000000000000000000000006,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x4200000000000000000000000000000000000006;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x4200000000000000000000000000000000000042;
        _setSwapPath(
            0x4200000000000000000000000000000000000006,
            0x4200000000000000000000000000000000000042,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x4200000000000000000000000000000000000042;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x4200000000000000000000000000000000000006;
        _setSwapPath(
            0x4200000000000000000000000000000000000042,
            0x4200000000000000000000000000000000000006,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );

        _path[0] = 0x4200000000000000000000000000000000000006;
        _path[1] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
        _path[2] = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;
        _setSwapPath(
            0x4200000000000000000000000000000000000006,
            0x3c8B650257cFb5f272f799F5e2b4e65093a11a05,
            0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9,
            _path
        );
    }

    function _getRouter(
        address /* _lpToken */
    ) internal view override returns (address) {
        return VELODROME_ROUTER;
    }

    function _swap(
        address _fromToken,
        address _toToken,
        uint256 _amount
    ) internal override returns (uint256 _toTokenAmount) {
        if (_fromToken == _toToken) return _amount;
        SwapPath memory _swapPath = getSwapPath(_fromToken, _toToken);

        route[] memory _routes = new route[](_swapPath.path.length - 1);

        uint256 _lastAmountBack = _amount;
        for (uint256 i; i < _swapPath.path.length - 1; i++) {
            (uint256 _amountBack, bool _stable) = IVelodromeRouter(
                _swapPath.unirouter
            ).getAmountOut(
                    _lastAmountBack,
                    _swapPath.path[i],
                    _swapPath.path[i + 1]
                );
            _lastAmountBack = _amountBack;
            _routes[i] = route({
                from: _swapPath.path[i],
                to: _swapPath.path[i + 1],
                stable: _stable
            });
        }

        IERC20(_fromToken).safeApprove(_swapPath.unirouter, 0);
        IERC20(_fromToken).safeApprove(_swapPath.unirouter, type(uint256).max);

        // debugging: uncomment this block
        // console.log("_inputAmount", _amount);
        // console.log("_fromToken:", IERC20Metadata(_fromToken).symbol());
        // console.log("_toToken:", IERC20Metadata(_toToken).symbol());
        // console.log("_path:");
        // for (uint256 i; i < _swapPath.path.length - 1; i++) {
        //     console.log(IERC20Metadata(_swapPath.path[i]).symbol());
        //     console.log("isStable:", _routes[i].stable);
        // }
        // console.log(
        //     IERC20Metadata(_swapPath.path[_swapPath.path.length - 1]).symbol()
        // );

        uint256 _toTokenBefore = IERC20(_toToken).balanceOf(address(this));
        IVelodromeRouter(_swapPath.unirouter).swapExactTokensForTokens(
            _amount,
            0,
            _routes,
            address(this),
            block.timestamp
        );

        _toTokenAmount =
            IERC20(_toToken).balanceOf(address(this)) -
            _toTokenBefore;

        //console.log("_toTokenAmount:", _toTokenAmount);
    }

    function _addLiquidity(
        address _router,
        address _token0,
        address _token1,
        uint256 _token0Out,
        uint256 _token1Out,
        bool _stable
    ) internal override {
        IVelodromeRouter(_router).addLiquidity(
            _token0,
            _token1,
            _stable,
            _token0Out,
            _token1Out,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function _removeLiquidity(
        address _router,
        address _token0,
        address _token1,
        uint256 _amountLpIn,
        bool _stable
    ) internal override {
        IVelodromeRouter(_router).removeLiquidity(
            _token0,
            _token1,
            _stable,
            _amountLpIn,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function _unzapFromLp(
        address _fromLpToken,
        address _toToken,
        uint256 _amountLpIn,
        uint256 _minAmountOut
    ) internal override returns (uint256 _amountOut) {
        address _router = _getRouter(_fromLpToken);

        bool _isStable = IUniswapV2Pair(_fromLpToken).stable();
        address _token0 = IUniswapV2Pair(_fromLpToken).token0();
        address _token1 = IUniswapV2Pair(_fromLpToken).token1();

        IERC20(_fromLpToken).safeApprove(_router, 0);
        IERC20(_fromLpToken).safeApprove(_router, _amountLpIn);

        _removeLiquidity(_router, _token0, _token1, _amountLpIn, _isStable);

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

        require(_amountOut >= _minAmountOut, "slippage-rekt-you");

        if (_toToken == WETH) {
            IWETH(WETH).withdraw(_amountOut);

            (bool _success, ) = msg.sender.call{value: _amountOut}("");
            require(_success, "eth-transfer-failed");
        } else {
            IERC20(_toToken).transfer(msg.sender, _amountOut);
        }
    }

    function _getRatio(address _lpToken) internal view returns (uint256) {
        address _token0 = IUniswapV2Pair(_lpToken).token0();
        address _token1 = IUniswapV2Pair(_lpToken).token1();

        (uint256 opLp0, uint256 opLp1, ) = IUniswapV2Pair(_lpToken)
            .getReserves();
        uint256 lp0Amt = (opLp0 * (10**18)) /
            (10**IERC20Metadata(_token0).decimals());
        uint256 lp1Amt = (opLp1 * (10**18)) /
            (10**IERC20Metadata(_token1).decimals());
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
            require(_fromToken == WETH, "invalid-from-token");
            require(_amountIn == msg.value, "invalid-amount-in");
            // Auto-wrap FTM to WETH
            IWETH(WETH).deposit{value: msg.value}();
        } else {
            IERC20(_fromToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amountIn
            );
        }

        address _router = _getRouter(_toLpToken);

        IERC20(_fromToken).safeApprove(_router, 0);
        IERC20(_fromToken).safeApprove(_router, _amountIn);

        bool _isStable = IUniswapV2Pair(_toLpToken).stable();
        address _token0 = IUniswapV2Pair(_toLpToken).token0();
        address _token1 = IUniswapV2Pair(_toLpToken).token1();

        address _defaultRouter = unirouter;
        unirouter = _router;
        // Uses lpToken' _router as the default router
        // You can override this by using setting a custom path
        // Using setSwapPath

        uint256 _token0Out;
        uint256 _token1Out;

        if (!_isStable) {
            _token0Out = _swap(_fromToken, _token0, _amountIn / 2);
            _token1Out = _swap(
                _fromToken,
                _token1,
                _amountIn - (_amountIn / 2)
            );
        } else {
            uint256 _amount0In = (_amountIn * _getRatio(_toLpToken)) / 10**18;
            uint256 _amount1In = _amountIn - _amount0In;
            _token0Out = _swap(_fromToken, _token0, _amount0In);
            _token1Out = _swap(_fromToken, _token1, _amount1In);
        }

        // Revert back to defaultRouter for swaps
        unirouter = _defaultRouter;

        IERC20(_token0).safeApprove(_router, 0);
        IERC20(_token1).safeApprove(_router, 0);
        IERC20(_token0).safeApprove(_router, _token0Out);
        IERC20(_token1).safeApprove(_router, _token1Out);

        uint256 _lpBalanceBefore = IERC20(_toLpToken).balanceOf(address(this));

        _addLiquidity(
            _router,
            _token0,
            _token1,
            _token0Out,
            _token1Out,
            _isStable
        );

        _lpAmountOut =
            IERC20(_toLpToken).balanceOf(address(this)) -
            _lpBalanceBefore;
        require(_lpAmountOut >= _minLpAmountOut, "slippage-rekt-you");
    }
}


//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./ISolidlyRouter.sol";
import "./IWETH.sol";
import "./IMatrixVault.sol";
import "./MatrixSwapHelperV2.sol";
import "./console.sol";

contract ZapperArbitrumV3 is MatrixSwapHelperV2, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event DefaultRouterChanged(address indexed _oldRouter, address indexed _newRouter);
    event CustomRouterSet(address indexed _lpToken, address indexed _customRouter);

    event ZapIn(address indexed _user, address indexed _vault, address indexed _want, uint256 _amountIn);

    event ZapOut(address indexed _user, address indexed _vault, address indexed _want, uint256 _amountOut);

    string public constant VERSION = '1.2';

    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address internal constant SUSHI_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address internal constant SWAPFISH_ROUTER = 0xcDAeC65495Fa5c0545c5a405224214e3594f30d8;
    address internal constant RAMSES_ROUTER = 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e;
    address internal constant CAMELOT_ROUTER = 0xc873fEcbd354f5A56E00E710B90EF4201db2448d;

    /// @dev Mapping of LP ERC20 -> Router
    /// In order to support a wider range of UniV2 forks
    mapping(address => address) public customRouter;

    mapping(address => MatrixSwapHelperV2.RouterType) public routerToType;

    /// @dev Mapping of Factory -> Router to retrieve
    /// the default router for LP token
    mapping(address => address) public factoryToRouter;

    /// @notice SushiSwap ROUTER AS DEFAULT FOR LP TOKENS AND SWAPS
    constructor() MatrixSwapHelperV2(SUSHI_ROUTER) {
        // SushiSwap Arbitrum
        factoryToRouter[0xc35DADB65012eC5796536bD9864eD8773aBc74C4] = SUSHI_ROUTER;
        routerToType[SUSHI_ROUTER] = MatrixSwapHelperV2.RouterType.UniV2;

        // Swapfish
        factoryToRouter[0x71539D09D3890195dDa87A6198B98B75211b72F3] = SWAPFISH_ROUTER;
        routerToType[SWAPFISH_ROUTER] = MatrixSwapHelperV2.RouterType.UniV2;

        // Ramses
        factoryToRouter[0xAAA20D08e59F6561f242b08513D36266C5A29415] = RAMSES_ROUTER;
        routerToType[RAMSES_ROUTER] = MatrixSwapHelperV2.RouterType.Solidly;

        // Camelot
        factoryToRouter[0x6EcCab422D763aC031210895C81787E87B43A652] = CAMELOT_ROUTER;
        routerToType[CAMELOT_ROUTER] = MatrixSwapHelperV2.RouterType.Camelot;

        routers.push(SUSHI_ROUTER);
        routers.push(SWAPFISH_ROUTER);
        routers.push(RAMSES_ROUTER);
        routers.push(CAMELOT_ROUTER);
    }

    receive() external payable {}

    /// @notice Get swap custom swap paths, if any
    /// @dev Otherwise reverts to default FROMTOKEN-WETH-TOTOKEN behavior
    function getSwapPath(
        address _fromToken,
        address _toToken,
        address _unirouter
    ) public view override returns (SwapPath memory _swapUniV2Path) {
        bytes32 _swapUniV2Key = keccak256(abi.encodePacked(_fromToken, _toToken, _unirouter));
        if (swapPaths[_swapUniV2Key].path.length == 0) {
            if (_fromToken != WETH && _toToken != WETH) {
                address[] memory _path = new address[](3);
                _path[0] = _fromToken;
                _path[1] = WETH;
                _path[2] = _toToken;
                _swapUniV2Path.path = _path;
            } else {
                address[] memory _path = new address[](2);
                _path[0] = _fromToken;
                _path[1] = _toToken;
                _swapUniV2Path.path = _path;
            }
            _swapUniV2Path.unirouter = _unirouter;
        } else {
            return swapPaths[_swapUniV2Key];
        }
    }

    /// @dev Allows owner to set a custom swap path from a token to another
    /// @param _unirouter Can also set a custom unirouter for the swap, or address(0) for default router (spooky)
    function setSwapPath(
        address _fromToken,
        address _toToken,
        address _unirouter,
        address[] memory _path
    ) external onlyOwner {
        _setSwapPath(_fromToken, _toToken, _unirouter, _path);
    }

    function zapToLp(
        address _fromToken,
        address _toLpToken,
        uint256 _amountIn,
        uint256 _minLpAmountOut
    ) external payable {
        uint256 _lpAmountOut = _zapToLp(_fromToken, _toLpToken, _amountIn, _minLpAmountOut);

        IERC20(_toLpToken).safeTransfer(msg.sender, _lpAmountOut);
    }

    function zapToMatrix(
        address _fromToken,
        address _matrixVault,
        uint256 _amountIn,
        uint256 _minLpAmountOut
    ) external payable {
        IMatrixVault _vault = IMatrixVault(_matrixVault);

        address _toLpToken = _vault.want();

        uint256 _lpAmountOut = _zapToLp(_fromToken, _toLpToken, _amountIn, _minLpAmountOut);

        uint256 _vaultBalanceBefore = _vault.balanceOf(address(this));

        IERC20(_toLpToken).safeApprove(_matrixVault, _lpAmountOut);

        _vault.deposit(_lpAmountOut);

        uint256 _vaultAmountOut = _vault.balanceOf(address(this)) - _vaultBalanceBefore;

        require(_vaultAmountOut > 0, 'deposit-in-vault-failed');

        _vault.transfer(msg.sender, _vaultAmountOut);

        emit ZapIn(msg.sender, address(_vault), _toLpToken, _lpAmountOut);
    }

    function unzapFromMatrix(
        address _matrixVault,
        address _toToken,
        uint256 _withdrawAmount,
        uint256 _minAmountOut
    ) external {
        IMatrixVault _vault = IMatrixVault(_matrixVault);
        address _fromLpToken = _vault.want();

        _vault.transferFrom(msg.sender, address(this), _withdrawAmount);
        _vault.withdraw(_withdrawAmount);

        uint256 _amountOut = _unzapFromLp(_fromLpToken, _toToken, IERC20(_fromLpToken).balanceOf(address(this)), _minAmountOut);

        emit ZapOut(msg.sender, address(_vault), _fromLpToken, _amountOut);
    }

    function unzapFromLp(
        address _fromLpToken,
        address _toToken,
        uint256 _amountLpIn,
        uint256 _minAmountOut
    ) external {
        IERC20(_fromLpToken).safeTransferFrom(msg.sender, address(this), _amountLpIn);
        _unzapFromLp(_fromLpToken, _toToken, _amountLpIn, _minAmountOut);
    }

    /// @notice In case tokens got stuck/mistakenly sent here
    function sweepERC20(address _token) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, IERC20(_token).balanceOf(_token));
    }

    function addRouter(
        address _factory,
        address _router,
        MatrixSwapHelperV2.RouterType _routerType
    ) external onlyOwner {
        require(factoryToRouter[_factory] == address(0), 'already-set');

        factoryToRouter[_factory] = _router;
        routerToType[_router] = _routerType;
    }

    function removeRouter(address _factory) external onlyOwner {
        require(factoryToRouter[_factory] != address(0), 'not-set');

        address _router = factoryToRouter[_factory];
        delete factoryToRouter[_factory];
        delete routerToType[_router];
    }

    function setCustomRouter(address lpToken, address router) external onlyOwner {
        // check if in whitelist
        for (uint256 i = 0; i < routers.length; i++) {
            if (routers[i] == router) {
                break;
            }
            if (i == routers.length - 1) {
                revert('router-not-whitelisted');
            }
        }

        customRouter[lpToken] = router;
    }

    /// @notice Get router for LPToken
    function _getRouter(address _lpToken) internal view virtual returns (address) {
        if (customRouter[_lpToken] != address(0)) return customRouter[_lpToken];

        address _factory = IUniswapV2Pair(_lpToken).factory();
        require(factoryToRouter[_factory] != address(0), 'unsupported-router');

        return factoryToRouter[_factory];
    }

    function getBestSwapPath(
        address fromToken,
        address toToken,
        uint256 amount
    ) public view returns (SwapPath memory _bestSwapPath) {
        address[] memory _routers = routers;
        uint256 _bestAmount = 0;

        for (uint256 i = 0; i < _routers.length; i++) {
            address _router = _routers[i];

            SwapPath memory _swapPath = getSwapPath(fromToken, toToken, _router);
            MatrixSwapHelperV2.RouterType _routerType = routerToType[_router];

            uint256 amountOut = _estimateSwap(_swapPath, amount, _routerType);

            if (amountOut > _bestAmount) {
                _bestAmount = amountOut;
                _bestSwapPath = _swapPath;
            }

            // testing direct path if weth is not present
            if (fromToken != WETH && toToken != WETH) {
                SwapPath memory _swapPathDirect;

                address[] memory _path = new address[](2);
                _path[0] = fromToken;
                _path[1] = toToken;

                _swapPathDirect.path = _path;
                _swapPathDirect.unirouter = _router;

                uint256 amountOutDirect = _estimateSwap(_swapPathDirect, amount, _routerType);

                if (amountOutDirect > _bestAmount) {
                    _bestAmount = amountOutDirect;
                    _bestSwapPath = _swapPathDirect;
                }
            }

            // testing usdc path if usdc is not present
            if (fromToken != USDC && toToken != USDC) {
                SwapPath memory _swapPathUSDC;

                address[] memory _path = new address[](3);
                _path[0] = fromToken;
                _path[1] = USDC;
                _path[2] = toToken;

                _swapPathUSDC.path = _path;
                _swapPathUSDC.unirouter = _router;

                uint256 amountOutUSDC = _estimateSwap(_swapPathUSDC, amount, _routerType);

                if (amountOutUSDC > _bestAmount) {
                    _bestAmount = amountOutUSDC;
                    _bestSwapPath = _swapPathUSDC;
                }
            }
        }

        require(_bestAmount > 0, 'no-path');
        return _bestSwapPath;
    }

    function _getRatio(address _lpToken) internal view returns (uint256) {
        (uint256 opLp0, uint256 opLp1, ) = IUniswapV2Pair(_lpToken).getReserves();
        uint256 lp0Amt = (opLp0 * (10**18)) / (10**IERC20Metadata(IUniswapV2Pair(_lpToken).token0()).decimals());
        uint256 lp1Amt = (opLp1 * (10**18)) / (10**IERC20Metadata(IUniswapV2Pair(_lpToken).token1()).decimals());
        uint256 totalSupply = lp0Amt + (lp1Amt);
        return (lp0Amt * (10**18)) / (totalSupply);
    }

    function _zapToLp(
        address _fromToken,
        address _toLpToken,
        uint256 _amountIn,
        uint256 _minLpAmountOut
    ) internal virtual returns (uint256 _lpAmountOut) {
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
        address _token0 = IUniswapV2Pair(_toLpToken).token0();
        address _token1 = IUniswapV2Pair(_toLpToken).token1();

        // Uses lpToken' _router as the default router
        // You can override this by using setting a custom path
        // Using setSwapPath
        SwapPath memory swapPathToken0 = getBestSwapPath(_fromToken, _token0, _amountIn / 2);
        SwapPath memory swapPathToken1 = getBestSwapPath(_fromToken, _token1, _amountIn - (_amountIn / 2));

        uint256 _token0Out;
        uint256 _token1Out;
        bool _isStable = false;

        if (routerToType[_router] == MatrixSwapHelperV2.RouterType.Solidly) {
            _isStable = IUniswapV2Pair(_toLpToken).stable();
        }

        if (!_isStable) {
            _token0Out = _swap(swapPathToken0, _amountIn / 2, routerToType[swapPathToken0.unirouter]);

            _token1Out = _swap(swapPathToken1, _amountIn - (_amountIn / 2), routerToType[swapPathToken1.unirouter]);
        } else {
            uint256 ratio = _getRatio(_toLpToken);
            uint256 _amount0In = (_amountIn * ratio) / 10**18;
            uint256 _amount1In = _amountIn - _amount0In;
            _token0Out = _swap(swapPathToken0, _amount0In, routerToType[swapPathToken0.unirouter]);
            _token1Out = _swap(swapPathToken1, _amount1In, routerToType[swapPathToken1.unirouter]);
        }

        IERC20(_token0).safeApprove(_router, 0);
        IERC20(_token1).safeApprove(_router, 0);
        IERC20(_token0).safeApprove(_router, _token0Out);
        IERC20(_token1).safeApprove(_router, _token1Out);

        uint256 _lpBalanceBefore = IERC20(_toLpToken).balanceOf(address(this));

        _addLiquidity(_router, _token0, _token1, _token0Out, _token1Out, _isStable);

        _lpAmountOut = IERC20(_toLpToken).balanceOf(address(this)) - _lpBalanceBefore;

        require(_lpAmountOut >= _minLpAmountOut, 'slippage-rekt-you');
    }

    function _addLiquidity(
        address _router,
        address _token0,
        address _token1,
        uint256 _token0Out,
        uint256 _token1Out,
        bool _stable
    ) internal virtual {
        MatrixSwapHelperV2.RouterType _routerType = routerToType[_router];

        if (_routerType == MatrixSwapHelperV2.RouterType.UniV2 || _routerType == MatrixSwapHelperV2.RouterType.Camelot) {
            IUniswapV2Router02(_router).addLiquidity(_token0, _token1, _token0Out, _token1Out, 0, 0, address(this), block.timestamp);
        } else if (_routerType == MatrixSwapHelperV2.RouterType.Solidly) {
            ISolidlyRouter(_router).addLiquidity(_token0, _token1, _stable, _token0Out, _token1Out, 0, 0, address(this), block.timestamp);
        } else {
            revert('invalid-router-type');
        }
    }

    function _removeLiquidity(
        address _router,
        address _token0,
        address _token1,
        uint256 _amountLpIn,
        bool _stable
    ) internal virtual {
        MatrixSwapHelperV2.RouterType _routerType = routerToType[_router];

        if (_routerType == MatrixSwapHelperV2.RouterType.UniV2 || _routerType == MatrixSwapHelperV2.RouterType.Camelot) {
            IUniswapV2Router02(_router).removeLiquidity(_token0, _token1, _amountLpIn, 0, 0, address(this), block.timestamp);
        } else if (_routerType == MatrixSwapHelperV2.RouterType.Solidly) {
            ISolidlyRouter(_router).removeLiquidity(_token0, _token1, _stable, _amountLpIn, 0, 0, address(this), block.timestamp);
        } else {
            revert('invalid-router-type');
        }
    }

    function _unzapFromLp(
        address _fromLpToken,
        address _toToken,
        uint256 _amountLpIn,
        uint256 _minAmountOut
    ) internal virtual returns (uint256 _amountOut) {
        address _router = _getRouter(_fromLpToken);

        address _token0 = IUniswapV2Pair(_fromLpToken).token0();
        address _token1 = IUniswapV2Pair(_fromLpToken).token1();

        IERC20(_fromLpToken).safeApprove(_router, 0);
        IERC20(_fromLpToken).safeApprove(_router, _amountLpIn);

        bool _isStable = false;

        if (routerToType[_router] == MatrixSwapHelperV2.RouterType.Solidly) {
            _isStable = IUniswapV2Pair(_fromLpToken).stable();
        }

        _removeLiquidity(_router, _token0, _token1, _amountLpIn, _isStable);

        // Uses lpToken' _router as the default router
        // You can override this by using setting a custom path
        // Using setSwapPath
        SwapPath memory swapPathToken0 = getBestSwapPath(_token0, _toToken, IERC20(_token0).balanceOf(address(this)));
        SwapPath memory swapPathToken1 = getBestSwapPath(_token1, _toToken, IERC20(_token1).balanceOf(address(this)));

        MatrixSwapHelperV2.RouterType path0RouterType = routerToType[swapPathToken0.unirouter];
        MatrixSwapHelperV2.RouterType path1RouterType = routerToType[swapPathToken1.unirouter];

        _swap(swapPathToken0, IERC20(_token0).balanceOf(address(this)), path0RouterType);
        _swap(swapPathToken1, IERC20(_token1).balanceOf(address(this)), path1RouterType);

        _amountOut = IERC20(_toToken).balanceOf(address(this));

        require(_amountOut >= _minAmountOut, 'slippage-rekt-you');

        if (_toToken == WETH) {
            IWETH(WETH).withdraw(_amountOut);

            (bool _success, ) = msg.sender.call{ value: _amountOut }('');
            require(_success, 'ftm-transfer-failed');
        } else {
            IERC20(_toToken).transfer(msg.sender, _amountOut);
        }
    }

    function _checkPath(address[] memory _path) internal override {}

    function _checkRouter(address _router) internal override {}
}


//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";
import "./IWFTM.sol";
import "./IMatrixVault.sol";
import "./MatrixSwapHelper.sol";

contract Zapper is MatrixSwapHelper, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event DefaultRouterChanged(
        address indexed _oldRouter,
        address indexed _newRouter
    );
    event CustomRouterSet(
        address indexed _lpToken,
        address indexed _customRouter
    );

    event ZapIn(
        address indexed _user,
        address indexed _vault,
        address indexed _want,
        uint256 _amountIn
    );

    event ZapOut(
        address indexed _user,
        address indexed _vault,
        address indexed _want,
        uint256 _amountOut
    );

    string public constant VERSION = "1.2";

    address public WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address internal constant SPOOKYSWAP_ROUTER =
        0xF491e7B69E4244ad4002BC14e878a34207E38c29;

    address internal constant BASED_ROUTER =
        0xaf2098E3AF3AC27a3a9362ACa2D883eFC36c7FAC;
    /// @dev Mapping of LP ERC20 -> Router
    /// In order to support a wider range of UniV2 forks
    mapping(address => address) public customRouter;

    /// @dev Mapping of Factory -> Router to retrieve
    /// the default router for LP token
    mapping(address => address) public factoryToRouter;

    /// @dev Default router for LP Tokens
    address public defaultRouter;

    /// @notice SPOOKYSWAP ROUTER AS DEFAULT FOR LP TOKENS AND SWAPS
    constructor() MatrixSwapHelper(BASED_ROUTER) {
        /// Default router to put LPs in:
        _setDefaultRouter(BASED_ROUTER);

        // Factory to Router
        // spookyswap
        factoryToRouter[
            0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3
        ] = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;

        // spiritswap
        factoryToRouter[
            0xEF45d134b73241eDa7703fa787148D9C9F4950b0
        ] = 0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52;

        // tombswap
        factoryToRouter[
            0xE236f6890F1824fa0a7ffc39b1597A5A6077Cfe9
        ] = 0x6D0176C5ea1e44b08D3dd001b0784cE42F47a3A7;

        // hyperjump
        factoryToRouter[
            0x991152411A7B5A14A8CF0cDDE8439435328070dF
        ] = 0x53c153a0df7E050BbEFbb70eE9632061f12795fB;

        // wigoswap
        factoryToRouter[
            0xC831A5cBfb4aC2Da5ed5B194385DFD9bF5bFcBa7
        ] = 0x5023882f4D1EC10544FCB2066abE9C1645E95AA0;

        // based
        factoryToRouter[
            0x407C47E3FDB7952Ee53aa232B5f28566A024A759
        ] = 0xaf2098E3AF3AC27a3a9362ACa2D883eFC36c7FAC;
    }

    receive() external payable {}

    /// @notice Get swap custom swap paths, if any
    /// @dev Otherwise reverts to default FROMTOKEN-WFTM-TOTOKEN behavior
    function getSwapPath(address _fromToken, address _toToken)
        public
        view
        override
        returns (SwapPath memory _swapPath)
    {
        bytes32 _swapKey = keccak256(abi.encodePacked(_fromToken, _toToken));
        if (swapPaths[_swapKey].path.length == 0) {
            if (_fromToken != WFTM && _toToken != WFTM) {
                address[] memory _path = new address[](3);
                _path[0] = _fromToken;
                _path[1] = WFTM;
                _path[2] = _toToken;
                _swapPath.path = _path;
            } else {
                address[] memory _path = new address[](2);
                _path[0] = _fromToken;
                _path[1] = _toToken;
                _swapPath.path = _path;
            }
            _swapPath.unirouter = unirouter;
        } else {
            return swapPaths[_swapKey];
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
        uint256 _lpAmountOut = _zapToLp(
            _fromToken,
            _toLpToken,
            _amountIn,
            _minLpAmountOut
        );

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

        uint256 _lpAmountOut = _zapToLp(
            _fromToken,
            _toLpToken,
            _amountIn,
            _minLpAmountOut
        );

        uint256 _vaultBalanceBefore = _vault.balanceOf(address(this));
        IERC20(_toLpToken).safeApprove(_matrixVault, _lpAmountOut);
        _vault.deposit(_lpAmountOut);
        uint256 _vaultAmountOut = _vault.balanceOf(address(this)) -
            _vaultBalanceBefore;
        require(_vaultAmountOut > 0, "deposit-in-vault-failed");
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

        uint256 _amountOut = _unzapFromLp(
            _fromLpToken,
            _toToken,
            IERC20(_fromLpToken).balanceOf(address(this)),
            _minAmountOut
        );

        emit ZapOut(msg.sender, address(_vault), _fromLpToken, _amountOut);
    }

    function unzapFromLp(
        address _fromLpToken,
        address _toToken,
        uint256 _amountLpIn,
        uint256 _minAmountOut
    ) external {
        IERC20(_fromLpToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amountLpIn
        );
        _unzapFromLp(_fromLpToken, _toToken, _amountLpIn, _minAmountOut);
    }

    /// @notice In case tokens got stuck/mistakenly sent here
    function sweepERC20(address _token) external onlyOwner {
        IERC20(_token).safeTransfer(
            msg.sender,
            IERC20(_token).balanceOf(_token)
        );
    }

    function setDefaultRouter(address _newDefaultRouter) external onlyOwner {
        _setDefaultRouter(_newDefaultRouter);
    }

    function setCustomRouter(address _token, address _router)
        external
        onlyOwner
    {
        require(_token != address(0), "invalid-token-addr");
        require(_router != defaultRouter, "invalid-custom-router");
        emit CustomRouterSet(_token, _router);
        customRouter[_token] = _router;
    }

    function _setDefaultRouter(address _newDefaultRouter) internal {
        require(_newDefaultRouter != address(0), "invalid-default-router");
        emit DefaultRouterChanged(defaultRouter, _newDefaultRouter);
        defaultRouter = _newDefaultRouter;
    }

    function addRouter(address _factory, address _router) external onlyOwner {
        require(factoryToRouter[_factory] == address(0), "already-set");

        factoryToRouter[_factory] = _router;
    }

    /// @notice Get router for LPToken
    function _getRouter(address _lpToken)
        internal
        view
        virtual
        returns (address)
    {
        if (customRouter[_lpToken] != address(0)) return customRouter[_lpToken];

        address _factory = IUniswapV2Pair(_lpToken).factory();
        require(factoryToRouter[_factory] != address(0), "unsupported-router");

        return factoryToRouter[_factory];
    }

    function _zapToLp(
        address _fromToken,
        address _toLpToken,
        uint256 _amountIn,
        uint256 _minLpAmountOut
    ) internal virtual returns (uint256 _lpAmountOut) {
        if (msg.value > 0) {
            // If you send FTM instead of WFTM these requirements must hold.
            require(_fromToken == WFTM, "invalid-from-token");
            require(_amountIn == msg.value, "invalid-amount-in");
            // Auto-wrap FTM to WFTM
            IWFTM(WFTM).deposit{value: msg.value}();
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

        address _token0 = IUniswapV2Pair(_toLpToken).token0();
        address _token1 = IUniswapV2Pair(_toLpToken).token1();

        address _defaultRouter = unirouter;
        unirouter = _router;
        // Uses lpToken' _router as the default router
        // You can override this by using setting a custom path
        // Using setSwapPath

        uint256 _token0Out = _swap(_fromToken, _token0, _amountIn / 2);
        uint256 _token1Out = _swap(
            _fromToken,
            _token1,
            _amountIn - (_amountIn / 2)
        );

        // Revert back to defaultRouter for swaps
        unirouter = _defaultRouter;

        IERC20(_token0).safeApprove(_router, 0);
        IERC20(_token1).safeApprove(_router, 0);
        IERC20(_token0).safeApprove(_router, _token0Out);
        IERC20(_token1).safeApprove(_router, _token1Out);

        uint256 _lpBalanceBefore = IERC20(_toLpToken).balanceOf(address(this));
        IUniswapV2Router02(_router).addLiquidity(
            _token0,
            _token1,
            _token0Out,
            _token1Out,
            0,
            0,
            address(this),
            block.timestamp
        );

        _lpAmountOut =
            IERC20(_toLpToken).balanceOf(address(this)) -
            _lpBalanceBefore;
        require(_lpAmountOut >= _minLpAmountOut, "slippage-rekt-you");
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

        IUniswapV2Router02(_router).removeLiquidity(
            _token0,
            _token1,
            _amountLpIn,
            0,
            0,
            address(this),
            block.timestamp
        );

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

        if (_toToken == WFTM) {
            IWFTM(WFTM).withdraw(_amountOut);

            (bool _success, ) = msg.sender.call{value: _amountOut}("");
            require(_success, "ftm-transfer-failed");
        } else {
            IERC20(_toToken).transfer(msg.sender, _amountOut);
        }
    }

    function _checkPath(address[] memory _path) internal override {}

    function _checkRouter(address _router) internal override {}
}


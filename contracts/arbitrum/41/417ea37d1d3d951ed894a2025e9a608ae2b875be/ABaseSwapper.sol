// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./SafeERC20.sol";
import "./Ownable.sol";

import "./IUniswapV2Router02.sol";

error UniswapV2Router02NotFound(uint256 _id);

abstract contract ABaseSwapper is Ownable {
    using SafeERC20 for IERC20;

    IUniswapV2Router02[] public swapRouters;

    constructor(IUniswapV2Router02[] memory _swapRouters) {
        swapRouters = _swapRouters;
    }

    function getSwapRouterCount() public view returns (uint256) {
        return swapRouters.length;
    }

    function addSwapRouter(IUniswapV2Router02 _router) external onlyOwner {
        swapRouters.push(_router);
    }

    function setSwapRouter(uint256 routerId, IUniswapV2Router02 _router)
        external
        onlyOwner
    {
        if (swapRouters.length < type(uint256).max)
            revert UniswapV2Router02NotFound(routerId);
        swapRouters[routerId] = _router;
    }

    // _routerId: 0 for uniswap, 1 for sushiswap
    function _calculateMinETHInputForOutputTokens(
        address _outputERC20,
        uint256 _outputERC20Amount,
        uint256 _routerId
    ) internal view returns (uint256[] memory) {
        address[] memory path = new address[](2);
        IUniswapV2Router02 router = swapRouters[_routerId];
        path[0] = router.WETH();
        path[1] = _outputERC20;
        return router.getAmountsIn(_outputERC20Amount, path);
    }

    // _routerId: 0 for uniswap, 1 for sushiswap
    function _calculateMinTokensInputForOutputTokens(
        address _inputERC20,
        address _outputERC20,
        uint256 _outputERC20Amount,
        uint256 _routerId
    ) internal view returns (uint256[] memory) {
        address[] memory path = new address[](2);
        IUniswapV2Router02 router = swapRouters[_routerId];
        path[0] = _inputERC20;
        path[1] = address(_outputERC20);
        return router.getAmountsIn(_outputERC20Amount, path);
    }

    // _routerId: 0 for uniswap, 1 for sushiswap
    function _swapTokensForExactTokens(
        address _inputERC20,
        address _outputERC20,
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256 _routerId,
        uint256 _deadline
    ) internal returns (uint256[] memory) {
        address[] memory path = new address[](2);
        IUniswapV2Router02 router = swapRouters[_routerId];
        path[0] = _inputERC20;
        path[1] = address(_outputERC20);
        IERC20(_inputERC20).approve(address(router), _amountInMax);
        return
            router.swapTokensForExactTokens(
                _amountOut,
                _amountInMax,
                path,
                address(this),
                _deadline
            );
    }

    // _routerId: 0 for uniswap, 1 for sushiswap
    function _swapExactTokensForTokens(
        address _inputERC20,
        address _outputERC20,
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256 _routerId,
        uint256 _deadline
    ) internal returns (uint256[] memory) {
        address[] memory path = new address[](2);
        IUniswapV2Router02 router = swapRouters[_routerId];
        path[0] = _inputERC20;
        path[1] = address(_outputERC20);
        IERC20(_inputERC20).approve(address(router), _amountIn);
        return
            router.swapExactTokensForTokens(
                _amountIn,
                _amountOutMin,
                path,
                address(this),
                _deadline
            );
    }

    // _routerId: 0 for uniswap, 1 for sushiswap
    function _swapExactETHForTokens(
        address _outputERC20,
        uint256 _amountOutMin,
        uint256 _routerId,
        uint256 _deadline
    ) internal returns (uint256[] memory) {
        address[] memory path = new address[](2);
        IUniswapV2Router02 router = swapRouters[_routerId];
        path[0] = router.WETH();
        path[1] = address(_outputERC20);
        return
            router.swapExactETHForTokens{value: msg.value}(
                _amountOutMin,
                path,
                address(this),
                _deadline
            );
    }

    // _routerId: 0 for uniswap, 1 for sushiswap
    function _swapETHForExactTokens(
        address _outputERC20,
        uint256 _amountOut,
        uint256 _routerId,
        uint256 _deadline
    ) internal returns (uint256[] memory) {
        address[] memory path = new address[](2);
        IUniswapV2Router02 router = swapRouters[_routerId];
        path[0] = router.WETH();
        path[1] = address(_outputERC20);
        return
            router.swapETHForExactTokens{value: msg.value}(
                _amountOut,
                path,
                address(this),
                _deadline
            );
    }

    // _routerId: 0 for uniswap, 1 for sushiswap
    function _swapExactTokensForETH(
        address _inputERC20,
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256 _routerId,
        uint256 _deadline
    ) internal returns (uint256[] memory) {
        address[] memory path = new address[](2);
        IUniswapV2Router02 router = swapRouters[_routerId];
        path[0] = address(_inputERC20);
        path[1] = router.WETH();
        IERC20(_inputERC20).approve(address(router), _amountIn);
        return
            router.swapExactTokensForETH(
                _amountIn,
                _amountOutMin,
                path,
                address(this),
                _deadline
            );
    }

    // _routerId: 0 for uniswap, 1 for sushiswap
    function _swapTokensForExactETH(
        address _inputERC20,
        uint256 _amountIn,
        uint256 _amountOutMax,
        uint256 _routerId,
        uint256 _deadline
    ) internal returns (uint256[] memory) {
        address[] memory path = new address[](2);
        IUniswapV2Router02 router = swapRouters[_routerId];
        path[0] = address(_inputERC20);
        path[1] = router.WETH();
        IERC20(_inputERC20).approve(address(router), _amountIn);
        return
            router.swapTokensForExactETH(
                _amountIn,
                _amountOutMax,
                path,
                address(this),
                _deadline
            );
    }
}


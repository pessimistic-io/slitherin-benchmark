pragma solidity 0.8.18;

import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IPool} from "./IPool.sol";
import {IWETH} from "./IWETH.sol";
import {ILPToken} from "./ILPToken.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";

/// @title Liquidity Router
/// @notice helper to add/remove liquidity and wrap/unwrap ETH as needed
contract LiquidityRouter {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    IPool public immutable pool;
    IWETH public immutable weth;

    constructor(address _pool, address _weth) {
        require(_pool != address(0), "zeroAddress");
        require(_weth != address(0), "zeroAddress");

        pool = IPool(_pool);
        weth = IWETH(_weth);
    }

    function addLiquidityETH(address _tranche, uint256 _minLpAmount, address _to) external payable {
        uint256 amountIn = msg.value;
        weth.deposit{value: amountIn}();
        weth.safeIncreaseAllowance(address(pool), amountIn);
        pool.addLiquidity(_tranche, address(weth), amountIn, _minLpAmount, _to);
    }

    function addLiquidity(address _tranche, address _token, uint256 _amountIn, uint256 _minLpAmount, address _to)
        external
    {
        IERC20 token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), _amountIn);
        token.safeIncreaseAllowance(address(pool), _amountIn);
        pool.addLiquidity(_tranche, _token, _amountIn, _minLpAmount, _to);
    }

    function removeLiquidityETH(address _tranche, uint256 _lpAmount, uint256 _minOut, address payable _to)
        external
        payable
    {
        IERC20 lpToken = IERC20(_tranche);
        lpToken.safeTransferFrom(msg.sender, address(this), _lpAmount);
        lpToken.safeIncreaseAllowance(address(pool), _lpAmount);
        uint256 balanceBefore = weth.balanceOf(address(this));
        pool.removeLiquidity(_tranche, address(weth), _lpAmount, _minOut, address(this));
        uint256 received = weth.balanceOf(address(this)) - balanceBefore;
        weth.withdraw(received);
        SafeTransferLib.safeTransferETH(_to, received);
    }

    function removeLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _to)
        external
    {
        IERC20 lpToken = IERC20(_tranche);
        lpToken.safeTransferFrom(msg.sender, address(this), _lpAmount);
        lpToken.safeIncreaseAllowance(address(pool), _lpAmount);
        pool.removeLiquidity(_tranche, _tokenOut, _lpAmount, _minOut, _to);
    }

    receive() external payable {}
}


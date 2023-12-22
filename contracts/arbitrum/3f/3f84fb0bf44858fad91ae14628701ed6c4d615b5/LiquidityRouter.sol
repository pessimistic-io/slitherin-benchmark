// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { Initializable } from "./Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";

import { IPool } from "./IPool.sol";
import { IWETH } from "./IWETH.sol";
import { ILPToken } from "./ILPToken.sol";

/// @title Liquidity Router
/// @notice helper to add/remove liquidity and wrap/unwrap ETH as needed
contract LiquidityRouter is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    IWETH public weth;
    address public tradingPool;

    function initialize(address _pool, address _weth) external initializer {
        __Ownable_init();
        require(_weth != address(0), "ETHHelper:zeroAddress");
        weth = IWETH(_weth);
        tradingPool = _pool;
    }

    function addLiquidityETH(address _tranche, uint256 _minLpAmount, address _to) external payable {
        uint256 amountIn = msg.value;
        weth.deposit{ value: amountIn }();
        weth.safeIncreaseAllowance(tradingPool, amountIn);
        IPool(tradingPool).addLiquidity(_tranche, address(weth), amountIn, _minLpAmount, _to);
    }

    function addLiquidity(address _tranche, address _token, uint256 _amountIn, uint256 _minLpAmount, address _to) external {
        IERC20 token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), _amountIn);
        token.safeIncreaseAllowance(tradingPool, _amountIn);
        IPool(tradingPool).addLiquidity(_tranche, _token, _amountIn, _minLpAmount, _to);
    }

    function removeLiquidityETH(address _tranche, uint256 _lpAmount, uint256 _minOut, address payable _to) external payable {
        IERC20 lpToken = IERC20(_tranche);
        lpToken.safeTransferFrom(msg.sender, address(this), _lpAmount);
        lpToken.safeIncreaseAllowance(tradingPool, _lpAmount);
        uint256 balanceBefore = weth.balanceOf(address(this));
        IPool(tradingPool).removeLiquidity(_tranche, address(weth), _lpAmount, _minOut, address(this));
        uint256 received = weth.balanceOf(address(this)) - balanceBefore;
        weth.withdraw(received);
        safeTransferETH(_to, received);
    }

    function removeLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _to) external {
        IERC20 lpToken = IERC20(_tranche);
        lpToken.safeTransferFrom(msg.sender, address(this), _lpAmount);
        lpToken.safeIncreaseAllowance(tradingPool, _lpAmount);
        IPool(tradingPool).removeLiquidity(_tranche, _tokenOut, _lpAmount, _minOut, _to);
    }

    function safeTransferETH(address to, uint256 amount) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = to.call{ value: amount }(new bytes(0));
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }

    receive() external payable {}
}


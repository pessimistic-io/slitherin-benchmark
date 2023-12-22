// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
pragma abicoder v2;

import "./SafeERC20Upgradeable.sol";
import "./UpgradeableBase.sol";
import "./ISwap.sol";
import "./IUniswapV3.sol";

abstract contract SwapRouterBase is ISwapGatewayBase, UpgradeableBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address internal constant ZERO_ADDRESS = address(0);
    uint256 internal constant BASE = 10**18;
    address public swapRouter;
    address public wETH;

    event SetWETH(address wETH);
    event SetSwapRouter(address swapRouter);

    function __SwapRouterBase_init(address _swapRouter, address _wETH)
        public
        initializer
    {
        wETH = _wETH;
        swapRouter = _swapRouter;

        UpgradeableBase.initialize();
    }

    receive() external payable {}

    fallback() external payable {}

    /*** Owner function ***/

    /**
     * @notice Set wETH
     * @param _wETH Address of Wrapped ETH
     */
    function setWETH(address _wETH) external onlyOwnerAndAdmin {
        require(_wETH != ZERO_ADDRESS, "SG8");

        wETH = _wETH;
        emit SetWETH(_wETH);
    }

    /**
     * @notice Set SwapRouter
     * @param _swapRouter Address of swapRouter
     */
    function setSwapRouter(address _swapRouter) external onlyOwnerAndAdmin {
        require(swapRouter != ZERO_ADDRESS, "SG8");

        swapRouter = _swapRouter;

        emit SetSwapRouter(swapRouter);
    }

    /*** Internal Function ***/

    /**
     * @notice Send ETH to address
     * @param _to target address to receive ETH
     * @param amount ETH amount (wei) to be sent
     */
    function _send(address payable _to, uint256 amount) internal {
        (bool sent, ) = _to.call{value: amount}("");
        require(sent, "SR1");
    }

    function _approveTokenForSwapRouter(
        address token,
        address _swapRouter,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20Upgradeable(token).allowance(
            address(this),
            _swapRouter
        );

        if (allowance == 0) {
            IERC20Upgradeable(token).safeApprove(_swapRouter, amount);
            return;
        }

        if (allowance < amount) {
            IERC20Upgradeable(token).safeIncreaseAllowance(
                _swapRouter,
                amount - allowance
            );
        }
    }

    function _findSwapPool(
        address tokenA,
        address tokenB,
        uint24 _fee,
        uint24[] memory fees
    ) internal view returns (address pool, uint24 fee) {
        if (_fee != 0) {
            pool = IUniswapV3Factory(IUniswapV3Router(swapRouter).factory())
                .getPool(tokenA, tokenB, _fee);

            require(pool != ZERO_ADDRESS, "SG2");
            fee = _fee;
        } else {
            uint256 length = fees.length;
            uint256 liquidity = 0;
            address factory = IUniswapV3Router(swapRouter).factory();

            for (uint8 i = 0; i < length; ) {
                address _pool = IUniswapV3Factory(factory).getPool(
                    tokenA,
                    tokenB,
                    fees[i]
                );
                if (_pool != ZERO_ADDRESS) {
                    uint256 _liquidity = _getPoolLiquidity(_pool);
                    if (_liquidity > liquidity) {
                        liquidity = _liquidity;
                        fee = fees[i];
                        pool = _pool;
                    }
                }
                unchecked {
                    ++i;
                }
            }

            require(fee > 0, "SG2");
        }
    }

    function _getPoolLiquidity(address pool)
        internal
        view
        virtual
        returns (uint256)
    {}
}


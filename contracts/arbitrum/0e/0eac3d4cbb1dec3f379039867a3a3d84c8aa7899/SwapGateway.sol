// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;
pragma abicoder v2;

import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./UpgradeableBase.sol";
import "./ISwap.sol";

contract SwapGateway is ISwapGateway, UpgradeableBase {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant ZERO_ADDRESS = address(0);
    address private wETH;

    mapping(address => address) swapRouterToCustom;

    event AddSwapRouter(address swapRouter, address swapRouterCustom);

    function __SwapGateway_init(address _wETH) public initializer {
        wETH = _wETH;
        UpgradeableBase.initialize();
    }

    receive() external payable {}

    fallback() external payable {}

    /*** Owner function ***/

    /**
     * @notice Add SwapRouter
     * @param swapRouter Address of swapRouter
     * @param swapRouterCustom Address of swapRouterXXX Contracts
     */
    function addSwapRouterCustom(address swapRouter, address swapRouterCustom)
        external
        onlyOwnerAndAdmin
    {
        require(swapRouterToCustom[swapRouter] == ZERO_ADDRESS, "SG8");

        swapRouterToCustom[swapRouter] = swapRouterCustom;
        emit AddSwapRouter(swapRouter, swapRouterCustom);
    }

    /**
     * @notice Get SwapRouter
     * @param swapRouter Address of swapRouter
     * @return swapRouterCustom Address of swapGateway Contracts
     */
    function getSwapRouterCustom(address swapRouter)
        external
        view
        returns (address)
    {
        return swapRouterToCustom[swapRouter];
    }

    /*** Swap function ***/

    /**
     * @notice Swap tokens using swapRouter
     * @param swapRouter Address of swapRouter contract
     * @param amountIn Amount for in
     * @param amountOut Amount for out
     * @param path swap path, path[0] is in, path[last] is out
     * @param isExactInput true : swapExactTokensForTokens, false : swapTokensForExactTokens
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swap(
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        bool isExactInput,
        uint256 deadline
    ) external payable override returns (uint256[] memory amounts) {
        swap(swapRouter, amountIn, amountOut, path, 0, isExactInput, deadline);
    }

    /**
     * @notice Swap tokens using swapRouter
     * @param swapRouter Address of swapRouter contract
     * @param amountIn Amount for in
     * @param amountOut Amount for out
     * @param path swap path, path[0] is in, path[last] is out
     * @param fee fee of pool
     * @param isExactInput true : swapExactTokensForTokens, false : swapTokensForExactTokens
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swap(
        address swapRouter,
        uint256 amountIn,
        uint256 amountOut,
        address[] memory path,
        uint24 fee,
        bool isExactInput,
        uint256 deadline
    ) public payable override returns (uint256[] memory amounts) {
        // Get SwapGatewayIndividual
        address swapRouterCustom = swapRouterToCustom[swapRouter];
        require(swapRouterCustom != ZERO_ADDRESS, "SG6");

        // Change ZERO_ADDRESS to WETH in path
        address _wETH = wETH;

        for (uint256 i = 0; i < path.length; ) {
            if (path[i] == ZERO_ADDRESS) path[i] = _wETH;
            unchecked {
                ++i;
            }
        }

        // Token Transfer and approve swap
        if (path[0] == _wETH) {
            require(msg.value >= amountIn, "SG0");

            // If too much ETH has been sent, send it back to sender
            if (msg.value > amountIn) {
                _send(payable(msg.sender), msg.value - amountIn);
            }
        } else {
            IERC20Upgradeable(path[0]).safeTransferFrom(
                msg.sender,
                address(this),
                amountIn
            );
            _approveTokenForSwapRouter(path[0], swapRouterCustom, amountIn);
        }

        // Swap
        if (isExactInput) {
            if (path[0] == _wETH) {
                ISwapGatewayBase(swapRouterCustom).swapExactIn{value: amountIn}(
                    amountIn,
                    amountOut,
                    path,
                    fee,
                    deadline
                );
            } else {
                ISwapGatewayBase(swapRouterCustom).swapExactIn(
                    amountIn,
                    amountOut,
                    path,
                    fee,
                    deadline
                );
            }
        } else {
            if (path[0] == _wETH) {
                ISwapGatewayBase(swapRouterCustom).swapExactOut{
                    value: amountIn
                }(amountOut, amountIn, path, fee, deadline);

                // send back remained token
                uint256 remainedToken = address(this).balance;
                if (remainedToken > 0) {
                    _send(payable(msg.sender), remainedToken);
                }
            } else {
                ISwapGatewayBase(swapRouterCustom).swapExactOut(
                    amountOut,
                    amountIn,
                    path,
                    fee,
                    deadline
                );

                // send back remained token
                uint256 remainedToken = IERC20Upgradeable(path[0]).balanceOf(
                    address(this)
                );
                if (remainedToken > 0) {
                    IERC20Upgradeable(path[0]).safeTransfer(
                        msg.sender,
                        remainedToken
                    );
                }
            }
        }

        // Back to msg.sender
        if (path[path.length - 1] == _wETH) {
            _send(payable(msg.sender), address(this).balance);
        } else {
            IERC20Upgradeable(path[path.length - 1]).safeTransfer(
                msg.sender,
                IERC20Upgradeable(path[path.length - 1]).balanceOf(
                    address(this)
                )
            );
        }
    }

    /**
     * @notice get swap out amount
     * @param swapRouter swap router address
     * @param amountIn amount of tokenIn : decimal = token.decimals;
     * @param path path of swap
     * @return amountOut amount of tokenOut : decimal = token.decimals;
     */
    function quoteExactInput(
        address swapRouter,
        uint256 amountIn,
        address[] memory path
    ) external view override returns (uint256 amountOut) {
        return quoteExactInput(swapRouter, 0, amountIn, path);
    }

    function quoteExactInput(
        address swapRouter,
        uint24 fee,
        uint256 amountIn,
        address[] memory path
    ) public view override returns (uint256 amountOut) {
        // Get SwapGatewayIndividual
        address swapRouterCustom = swapRouterToCustom[swapRouter];
        require(swapRouterCustom != ZERO_ADDRESS, "SG6");

        // Change ZERO_ADDRESS to wETH
        for (uint256 i = 0; i < path.length; ) {
            if (path[i] == ZERO_ADDRESS) path[i] = wETH;
            unchecked {
                ++i;
            }
        }

        amountOut = ISwapGatewayBase(swapRouterCustom).quoteExactInput(
            amountIn,
            path,
            fee
        );
    }

    function quoteExactOutput(
        address swapRouter,
        uint256 amountOut,
        address[] memory path
    ) external view override returns (uint256 amountIn) {
        return quoteExactOutput(swapRouter, 0, amountOut, path);
    }

    function quoteExactOutput(
        address swapRouter,
        uint24 fee,
        uint256 amountOut,
        address[] memory path
    ) public view override returns (uint256 amountIn) {
        // Get SwapGatewayIndividual
        address swapRouterCustom = swapRouterToCustom[swapRouter];
        require(swapRouterCustom != ZERO_ADDRESS, "SG6");

        // Change ZERO_ADDRESS to wETH
        for (uint256 i = 0; i < path.length; ) {
            if (path[i] == ZERO_ADDRESS) path[i] = wETH;
            unchecked {
                ++i;
            }
        }

        amountIn = ISwapGatewayBase(swapRouterCustom).quoteExactOutput(
            amountOut,
            path,
            fee
        );
    }

    /*** Private Function ***/

    /**
     * @notice Send ETH to address
     * @param _to target address to receive ETH
     * @param amount ETH amount (wei) to be sent
     */
    function _send(address payable _to, uint256 amount) private {
        (bool sent, ) = _to.call{value: amount}("");
        require(sent, "SR1");
    }

    function _approveTokenForSwapRouter(
        address token,
        address swapRouter,
        uint256 amount
    ) private {
        uint256 allowance = IERC20Upgradeable(token).allowance(
            address(this),
            swapRouter
        );

        if (allowance == 0) {
            IERC20Upgradeable(token).safeApprove(swapRouter, amount);
            return;
        }

        if (allowance < amount) {
            IERC20Upgradeable(token).safeIncreaseAllowance(
                swapRouter,
                amount - allowance
            );
        }
    }
}


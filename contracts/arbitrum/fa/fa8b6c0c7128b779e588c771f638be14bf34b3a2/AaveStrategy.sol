// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IERC20Metadata.sol";
import "./UUPSUpgradeable.sol";
import "./IPool.sol";
import "./IAaveOracle.sol";
import "./IAaveStrategy.sol";
import "./NonBlockingBaseApp.sol";

contract AaveStrategy is IAaveStrategy, NonBlockingBaseApp {
    IActionPoolDcRouter public actionPool;
    IAaveVault public aaveVault;
    IUniswapV2Router02 public uniswapV2Router;
    uint256 public chainId;

    modifier onlyActionPool() {
        require(
            msg.sender == address(actionPool) || msg.sender == address(this),
            "AaveStrategy::only action pool or self call"
        );
        _;
    }

    modifier onlyAaveVault() {
        require(
            msg.sender == address(aaveVault),
            "AaveStrategy::onlyAaveVault:Only AaveVault"
        );
        _;
    }

    receive() external payable override onlyAaveVault {}

    function initialize(bytes memory _data) public initializer {
        (
            IActionPoolDcRouter actionPoolDcRouterAddress,
            IAaveVault aaveVaultAddress,
            IUniswapV2Router02 uniswapRouterAddress
        ) = abi.decode(
                _data,
                (IActionPoolDcRouter, IAaveVault, IUniswapV2Router02)
            );
        require(
            address(uniswapRouterAddress) != address(0),
            "AaveStrategy::intialize: address zero"
        );
        require(
            address(aaveVaultAddress) != address(0),
            "AaveStrategy::intialize: address zero"
        );

        require(
            address(actionPoolDcRouterAddress) != address(0),
            "AaveStrategy::intialize: address zero"
        );
        actionPool = actionPoolDcRouterAddress;
        aaveVault = aaveVaultAddress;
        uniswapV2Router = uniswapRouterAddress;
        assembly {
            sstore(chainId.slot, chainid())
        }
    }

    function setUniswapRouter(address newRouter) external onlyOwner {
        uniswapV2Router = IUniswapV2Router02(newRouter);
        emit UniSwapRouterSet(newRouter, msg.sender);
    }

    /**
     * @notice Swap exact tokens for Tokens uniswap v2
     * @param _data : amountIn to swap for amountOut, swap path and tx deadline time
     */
    function swap(bytes memory _data)
        public
        override
        onlyActionPool
        returns (uint256 amountOut)
    {
        (
            uint256 amountIn,
            uint256 amountOutMin,
            address[] memory path,
            uint256 deadline
        ) = abi.decode(_data, (uint256, uint256, address[], uint256));
        require(amountIn > 0, "AaveStrategy::swap: wrong amountIn");
        require(path.length >= 2, "AaveStrategy::swap: wrong path");

        aaveVault.transferToStrategy(path[0], amountIn);

        if (address(path[0]) == address(0x0)) {
            // using avalanche id for joe trader swapExactTokensForAVAX
            if (chainId == 43114) {
                path[0] = uniswapV2Router.WAVAX();

                amountOut = uniswapV2Router.swapExactAVAXForTokens{
                    value: amountIn
                }(
                    amountOutMin,
                    path,
                    address(aaveVault),
                    block.timestamp + deadline
                )[path.length - 1];
            } else {
                path[0] = uniswapV2Router.WETH();
                amountOut = uniswapV2Router.swapExactETHForTokens{
                    value: amountIn
                }(
                    amountOutMin,
                    path,
                    address(aaveVault),
                    block.timestamp + deadline
                )[path.length - 1];
            }
        } else {
            if (address(path[path.length - 1]) == address(0x0)) {
                if (chainId == 43114) {
                    path[path.length - 1] = uniswapV2Router.WAVAX();
                } else {
                    path[path.length - 1] = uniswapV2Router.WETH();
                }
            }
            IERC20(path[0]).approve(address(uniswapV2Router), amountIn);
            amountOut = uniswapV2Router.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                address(aaveVault),
                block.timestamp + deadline
            )[path.length - 1];
        }
        emit SwapEvent(path, amountIn, amountOut);
    }

    /**
     * @notice Sell borrowed asset from aave
     * @param _data : MarginShort struct
     * @dev
     * 1. supply collateral
     * 2. borrow asset
     * 3. sell asset on uniswap
     * 4. resupply USDC after selling
     */
    function marginShort(bytes memory _data) public override onlyActionPool {
        MarginShort memory marginShortParams = abi.decode(_data, (MarginShort));
        require(
            marginShortParams.supplyAmount > 0,
            "AaveStrategy::marginShort: wrong supply amount"
        );
        require(
            marginShortParams.path.length >= 2,
            "AaveStrategy::marginShort: wrong path length"
        );
        // supply collateral
        address collateralAsset = marginShortParams.path[
            marginShortParams.path.length - 1
        ];
        if (collateralAsset == address(0)) {
            if (chainId == 43114) {
                collateralAsset = uniswapV2Router.WAVAX();
            } else {
                collateralAsset = uniswapV2Router.WETH();
            }
        }
        aaveVault.openPosition(
            abi.encode(
                marginShortParams.path[marginShortParams.path.length - 1],
                marginShortParams.supplyAmount,
                marginShortParams.referralCode
            )
        );
        // set collateral type before borrowing
        aaveVault.setCollateralAsset(abi.encodePacked(collateralAsset));

        // borrow amount
        (, , uint256 availableBorrowsBase, , , ) = IPool(
            aaveVault.aaveLendingPool()
        ).getUserAccountData(address(aaveVault));
        uint256 assetPrice = IAaveOracle(
            aaveVault.aaveProvider().getPriceOracle()
        ).getAssetPrice(
                marginShortParams.path[0] == address(0x0)
                    ? (
                        chainId == 43114
                            ? uniswapV2Router.WAVAX()
                            : uniswapV2Router.WETH()
                    )
                    : marginShortParams.path[0]
            );

        uint8 decimals = marginShortParams.path[0] == address(0x0)
            ? 18
            : IERC20Metadata(address(marginShortParams.path[0])).decimals();
        uint256 borrowAmount = (availableBorrowsBase * 10**decimals) /
            assetPrice;

        // borrow shorting asset
        aaveVault.borrow(
            abi.encode(
                marginShortParams.path[0],
                borrowAmount,
                marginShortParams.borrowRate,
                marginShortParams.referralCode
            )
        );

        uint256 amountOut = swap(
            abi.encode(
                borrowAmount,
                marginShortParams.tradeOutAmount,
                marginShortParams.path,
                marginShortParams.tradeDeadline
            )
        );
        require(
            IERC20(collateralAsset).balanceOf(address(aaveVault)) >= amountOut,
            "AaveStrategy::marginShort: borrowAsset balance less than borrow amount Out"
        );
        // supply more collateral
        aaveVault.openPosition(
            abi.encode(
                collateralAsset,
                amountOut,
                marginShortParams.referralCode
            )
        );

        emit MarginShortEvent(marginShortParams);
    }

    /**
     * @notice Decrease short position
     * @param _data : MarginShort struct
     * @dev
     * 1. withdraw collateral
     * 2. buy asset on uniswap
     * 3. repay asset
     */
    function decreaseMarginShort(bytes memory _data)
        public
        override
        onlyActionPool
    {
        DecreaseShort memory params = abi.decode(_data, (DecreaseShort));
        require(
            params.collateralAmount > 0,
            "AaveStrategy::decreaseShort: wrong collateral amount"
        );
        require(
            params.path.length >= 2,
            "AaveStrategy::decreaseShort: wrong path length"
        );
        address collateralAsset = params.path[0];
        address shortAsset = params.path[params.path.length - 1];

        // withdraw collateral
        aaveVault.closePosition(
            abi.encode(
                collateralAsset,
                params.collateralAmount,
                params.referralCode
            )
        );

        // swap collateral into shorting asset
        uint256 amountOut = swap(
            abi.encode(
                params.collateralAmount,
                params.tradeOutAmount,
                params.path,
                params.tradeDeadline
            )
        );
        require(
            IERC20(shortAsset).balanceOf(address(aaveVault)) >=
                params.tradeOutAmount,
            "AaveStrategy::decreaseShort: shortAsset balance less than trade amount Out"
        );

        // repay shorting asset
        aaveVault.repay(abi.encode(shortAsset, amountOut, params.borrowRate));

        emit DecreaseShortEvent(params);
    }

    uint256[50] private __gap;
}


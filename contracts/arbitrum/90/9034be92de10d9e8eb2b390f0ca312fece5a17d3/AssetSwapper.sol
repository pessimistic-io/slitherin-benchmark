// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IUniswapV3Router} from "./IUniswapV3Router.sol";
import {IGmxRouter} from "./IGmxRouter.sol";
import {IGmxReader} from "./IGmxReader.sol";

// Contracts
import {Ownable} from "./Ownable.sol";

/// @title Swaps tokens on Uniswap V2
/// @author Dopex
contract AssetSwapper is Ownable {
    using SafeERC20 for IERC20;

    /// @dev Uniswap V2 SwapRouter
    IUniswapV2Router02 public uniV2Router;

    /// @dev Uniswap V3 SwapRouter
    IUniswapV3Router public uniV3Router;

    /// @dev Gmx SwapRouter
    IGmxRouter public gmxRouter;

    /// @dev Gmx Reader
    IGmxReader public gmxReader;

    /// @dev Gmx Vault
    address public gmxVault;

    /// @dev weth address
    address public immutable weth;

    /// @dev max. price impact %
    uint256 public maxPriceImpact;

    uint256 public precision = 10 ** 6;

    event SetUniV2RouterAddress(address indexed swapper);
    event SetUniV3RouterAddress(address indexed swapper);
    event SetGmxRouterAddress(address indexed swapper);
    event SetGmxReaderAddress(address indexed reader);
    event SetGmxVaultAddress(address indexed vault);
    event SetMaxPriceImpact(uint256 indexed percentage);
    
    event Swap(
        uint256 indexed swapperId,
        address from,
        address to,
        uint256 amount,
        uint256 amountOut
    );
    
    constructor(address _uniV2Router, address _uniV3Router, address _gmxRouter, address _gmxReader, address _gmxVault, address _weth, uint256 _maxPriceImpact) {
        require(
            _uniV2Router != address(0) && _uniV3Router != address(0) && _gmxRouter != address(0) && _gmxReader != address(0),
            "Router address cannot be 0 address"
        );
        require(_weth != address(0), "WETH address cannot be 0 address");
        uniV2Router = IUniswapV2Router02(_uniV2Router);
        uniV3Router = IUniswapV3Router(_uniV3Router);
        gmxRouter = IGmxRouter(_gmxRouter);
        gmxReader = IGmxReader(_gmxReader);
        gmxVault = _gmxVault;
        weth = _weth;
        maxPriceImpact = _maxPriceImpact;

        emit SetUniV2RouterAddress(_uniV2Router);
        emit SetUniV3RouterAddress(_uniV3Router);
        emit SetGmxRouterAddress(_gmxRouter);
        emit SetGmxReaderAddress(_gmxReader);
        emit SetGmxVaultAddress(_gmxVault);
        emit SetMaxPriceImpact(_maxPriceImpact);
    }

    function setUniV2RouterAddress(address _address)
        external
        onlyOwner
        returns (bool)
    {
        require(_address != address(0), "address cannot be null");

        uniV2Router = IUniswapV2Router02(_address);

        emit SetUniV2RouterAddress(_address);

        return true;
    }

    function setUniV3RouterAddress(address _address)
        external
        onlyOwner
        returns (bool)
    {
        require(_address != address(0), "address cannot be null");

        uniV3Router = IUniswapV3Router(_address);

        emit SetUniV3RouterAddress(_address);

        return true;
    }

    function setGmxRouterAddress(address _address)
        external
        onlyOwner
        returns (bool)
    {
        require(_address != address(0), "address cannot be null");

        gmxRouter = IGmxRouter(_address);

        emit SetGmxRouterAddress(_address);

        return true;
    }

    function setGmxReaderAddress(address _address)
        external
        onlyOwner
        returns (bool)
    {
        require(_address != address(0), "address cannot be null");

        gmxReader = IGmxReader(_address);

        emit SetGmxReaderAddress(_address);

        return true;
    }

    function setMaxPriceImpact(uint256 _value)
        external
        onlyOwner
        returns (bool)
    {
        maxPriceImpact = _value;

        emit SetMaxPriceImpact(_value);

        return true;
    }

    function _checkPriceImpact(
        uint256 lastPrice,
        uint256 effectivePrice
    ) internal {
        require(((precision * lastPrice) / effectivePrice) <= maxPriceImpact + precision, "Price impact too high");
    }

    function _swapUsingUniV2(
        address from,
        address to,
        uint256 amount,
        uint256 minAmountOut
    ) internal returns (uint256) {
        address[] memory path;

        if (from == weth || to == weth) {
            path = new address[](2);
            path[0] = from;
            path[1] = to;
        } else {
            path = new address[](3);
            path[0] = from;
            path[1] = weth;
            path[2] = to;
        }

        IERC20(from).safeApprove(address(uniV2Router), amount);

        uint256 oneCent = (amount * 10 ** 4) / precision;
        uint256[] memory amounts = uniV2Router.getAmountsOut(oneCent, path);
        uint256 lastPrice = (10 ** 18) * amounts[1] / oneCent;

        uint256 amountOut = uniV2Router.swapExactTokensForTokens(
            amount,
            minAmountOut,
            path,
            address(this),
            block.timestamp
        )[path.length - 1];

        uint256 effectivePrice = (10 ** 18) * amountOut / amount;

        _checkPriceImpact(lastPrice, effectivePrice);

        return amountOut;
    }

    function _swapUsingUniV3(
        address from,
        address to,
        uint256 amount,
        uint256 minAmountOut
    ) internal returns (uint256) {
        IERC20(from).safeApprove(address(uniV3Router), amount);

        uint256 oneCent = (amount * 10 ** 4) / precision;
        uint256 remaining = amount - oneCent;

        IUniswapV3Router.ExactInputSingleParams memory firstSwapParams = IUniswapV3Router.ExactInputSingleParams(
            from, to, 500,
            address(this), block.timestamp, oneCent, 0, 0
        );

        IUniswapV3Router.ExactInputSingleParams memory secondSwapParams = IUniswapV3Router.ExactInputSingleParams(
            from, to, 500,
            address(this), block.timestamp, remaining, 0, 0
        );

        uint256 amountOutAfterFees = uniV3Router.exactInputSingle(firstSwapParams);
        uint256 lastPrice = (10 ** 18) * amountOutAfterFees / oneCent;

        uint256 amountOut = uniV3Router.exactInputSingle(secondSwapParams);

        require(amountOut > minAmountOut, "Invalid swap");

        uint256 effectivePrice = (10 ** 18) * amountOut / remaining;

        _checkPriceImpact(lastPrice, effectivePrice);

        return amountOut;
    }

    function _swapUsingGmx(
        address from,
        address to,
        uint256 amount,
        uint256 minAmountOut
    ) internal returns (uint256) {
        IERC20(from).safeApprove(address(gmxRouter), amount);

        uint256 initialAmountOut = IERC20(to).balanceOf(address(this));

        address[] memory path;

        path = new address[](2);
        path[0] = from;
        path[1] = to;

        uint256 oneCent = (amount * 10 ** 4) / precision;
        (uint256 amountOutAfterFees, ) = gmxReader.getAmountOut(gmxVault, from, to, oneCent);
        uint256 lastPrice = (10 ** 18) * amountOutAfterFees / oneCent;

        gmxRouter.swap(
            path,
            amount,
            minAmountOut,
            address(this)
        );

        uint256 amountOut = IERC20(to).balanceOf(address(this)) - initialAmountOut;

        uint256 effectivePrice = (10 ** 18) * amountOut / amount;

        _checkPriceImpact(lastPrice, effectivePrice);

        return amountOut;
    }

    /// @dev Swaps between given `from` and `to` assets
    /// @param from From token address
    /// @param to To token address
    /// @param amount From token amount
    /// @param minAmountOut Minimum token amount to receive out
    /// @return tokenOut token amount received
    function swapAsset(
        address from,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 swapperId
    ) external returns (uint256) {
        IERC20(from).safeTransferFrom(msg.sender, address(this), amount);

        uint256 amountOut = 0;

        if (swapperId == 0) {
            amountOut = _swapUsingUniV2(from, to, amount, minAmountOut);
        } else if (swapperId == 1) {
            amountOut = _swapUsingUniV3(from, to, amount, minAmountOut);
        } else if (swapperId == 2) {
            amountOut = _swapUsingGmx(from, to, amount, minAmountOut);
        } else if (swapperId == 3) {
            // use sushi to ETH then gmx
            amountOut = _swapUsingGmx(weth, to, _swapUsingUniV2(from, weth, amount, 0), minAmountOut);
        } else if (swapperId == 4) {
            // use sushi to ETH then uni v3
            amountOut = _swapUsingUniV3(weth, to, _swapUsingUniV2(from, weth, amount, 0), minAmountOut);
        }

        emit Swap(
            swapperId,
            from,
            to,
            amount,
            amountOut
        );

        IERC20(to).safeTransfer(msg.sender, amountOut);
        return amountOut;
    }
}


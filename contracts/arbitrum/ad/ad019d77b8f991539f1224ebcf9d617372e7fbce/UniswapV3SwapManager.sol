// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { BaseSwapManager } from "./BaseSwapManager.sol";
import { ERC20 } from "./ERC20.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import { UNISWAP_SWAP_ROUTER, UNISWAP_FACTORY } from "./constants.sol";

/**
 * @title UniswapV3SwapManager
 * @author Umami DAO
 * @notice Uniswap V3 implementation of the BaseSwapManager for swapping tokens.
 * @dev This contract uses the Uniswap V3 router for performing token swaps.
 */
contract UniswapV3SwapManager is BaseSwapManager {
    using SafeTransferLib for ERC20;

    // STORAGE
    // ------------------------------------------------------------------------------------------

    struct Config {
        uint24[] feeTiers;
        address intermediaryAsset;
    }

    /// @notice UniV3 router for calling swaps
    /// https://github.com/Uniswap/v3-periphery/blob/main/contracts/SwapRouter.sol
    ISwapRouter public constant uniV3Router = ISwapRouter(UNISWAP_SWAP_ROUTER);

    /// @notice UniV3 factory for discovering pools
    /// https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Factory.sol
    IUniswapV3Factory public constant uniV3factory = IUniswapV3Factory(UNISWAP_FACTORY);

    bytes32 public constant CONFIG_SLOT = keccak256("swapManagers.UniswapV3.config");
    address public immutable AGGREGATE_VAULT;

    constructor(address _aggregateVault, address _intermediaryAsset) {
        require(_aggregateVault != address(0), "!_aggregateVault");
        require(_intermediaryAsset != address(0), "!_intermediaryAsset");
        Config storage config = _configStorage();
        AGGREGATE_VAULT = _aggregateVault;
        config.intermediaryAsset = _intermediaryAsset;
    }

    // EXTERNAL
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Swaps tokens using the Uniswap V3 router.
     * @param _tokenIn The address of the input token.
     * @param _tokenOut The address of the output token.
     * @param _amountIn The amount of input tokens to swap.
     * @param _minOut The minimum amount of output tokens to receive.
     * @param - Encoded swap data (not used in this implementation).
     * @return _amountOut The actual amount of output tokens received.
     */
    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _minOut, bytes calldata)
        external
        onlyDelegateCall
        swapChecks(_tokenIn, _tokenOut, _amountIn, _minOut)
        returns (uint256 _amountOut)
    {
        bytes memory path = _getSwapPath(_tokenIn, _tokenOut);
        _amountOut = _swapTokenExactInput(_tokenIn, _amountIn, _minOut, path);
    }

    /**
     * @notice Swaps tokens using the Uniswap V3 router.
     * @param _tokenIn The address of the input token.
     * @param _tokenOut The address of the output token.
     * @param _amountOut The amount of output tokens to swap into.
     * @param _maxIn The maximum amount of input tokens that can be used.
     * @return _amountIn The actual amount of output tokens received.
     */
    function exactOutputSwap(address _tokenIn, address _tokenOut, uint256 _amountOut, uint256 _maxIn)
        external
        onlyDelegateCall
        swapChecks(_tokenIn, _tokenOut, _maxIn, _amountOut)
        returns (uint256 _amountIn)
    {
        bytes memory path = _getSwapPath(_tokenIn, _tokenOut);
        _amountIn = _swapTokenExactOutput(_tokenIn, _amountOut, _maxIn, path);
    }

    /**
     * @notice Adds a new fee tier.
     * @param _feeTier A fee tier to add.
     */
    function addFeeTier(uint24 _feeTier) external onlyDelegateCall {
        require(_feeTier > 0 && _feeTier < 100_000, "UniswapV3SwapManager: !_feeTier");
        Config storage config = _configStorage();
        config.feeTiers.push(_feeTier);
    }

    /**
     * @notice Removes an existing fee tier.
     * @param _feeTierToRemove A fee tier to remove.
     * @param _idx index of the tier.
     */
    function removeFeeTierAt(uint24 _feeTierToRemove, uint256 _idx) external onlyDelegateCall {
        Config storage config = _configStorage();
        require(config.feeTiers[_idx] == _feeTierToRemove, "UniswapV3SwapManager: invalid idx");
        config.feeTiers[_idx] = config.feeTiers[config.feeTiers.length - 1];
        config.feeTiers.pop();
    }

    /**
     * @notice Sets the intermediary asset used for swapping.
     * @param _newAsset The address of the new intermediary asset.
     */
    function setIntermediaryAsset(address _newAsset) external onlyDelegateCall {
        require(_newAsset != address(0), "UniswapV3SwapManager: !_newAsset");
        Config storage config = _configStorage();
        config.intermediaryAsset = _newAsset;
    }

    // INTERNAL
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Internal function to perform a token swap with exact input.
     * @param _tokenIn The address of the input token.
     * @param _amountIn The amount of input tokens to swap.
     * @param _minOut The minimum amount of output tokens to receive.
     * @param _path The encoded path for the swap.
     * @return _out The actual amount of output tokens received.
     */
    function _swapTokenExactInput(address _tokenIn, uint256 _amountIn, uint256 _minOut, bytes memory _path)
        internal
        returns (uint256 _out)
    {
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: _path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: _minOut
        });
        ERC20(_tokenIn).safeApprove(address(uniV3Router), _amountIn);
        return uniV3Router.exactInput(params);
    }

    /**
     * @notice Internal function to perform a token swap with exact input.
     * @param _tokenIn The address of the input token.
     * @param _amountOut The amount of output tokens to swap into.
     * @param _maxIn The maximum amount of input tokens to use.
     * @param _path The encoded path for the swap.
     * @return _in The actual amount of input tokens used.
     */
    function _swapTokenExactOutput(address _tokenIn, uint256 _amountOut, uint256 _maxIn, bytes memory _path)
        internal
        returns (uint256 _in)
    {
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: _path,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: _maxIn
        });
        ERC20(_tokenIn).safeApprove(address(uniV3Router), _maxIn);
        return uniV3Router.exactOutput(params);
    }

    /**
     * @notice Internal function to generate the swap path.
     * @param _tokenIn The address of the input token.
     * @param _tokenOut The address of the output token.
     * @return path The encoded swap path.
     */
    function _getSwapPath(address _tokenIn, address _tokenOut) internal view returns (bytes memory path) {
        Config storage config = _configStorage();
        uint24 tokenInFee = _getSwapFee(_tokenIn);
        uint24 tokenOutFee = _getSwapFee(_tokenOut);
        require(tokenInFee > 0, "UniswapV3SwapManager: !_tokenIn");
        require(tokenOutFee > 0, "UniswapV3SwapManager: !_tokenOut");
        require(_tokenIn != _tokenOut, "UniswapV3SwapManager: !unique tokens");
        if (_tokenIn == config.intermediaryAsset || _tokenOut == config.intermediaryAsset) {
            path = abi.encodePacked(_tokenIn, tokenInFee, _tokenOut);
        } else {
            path = abi.encodePacked(_tokenIn, tokenInFee, config.intermediaryAsset, tokenOutFee, _tokenOut);
        }
    }

    /**
     * @notice finds the pool with the highest balance of _balanceToken
     * @param _targetToken The address of the token recorded in config.
     * @return swapFee The fee for the pool with the highest balance of _balanceToken.
     */
    function _getSwapFee(address _targetToken) internal view returns (uint24 swapFee) {
        Config storage config = _configStorage();
        address bestSwapPool;
        address iterSwapPool;
        for (uint256 i = 0; i < config.feeTiers.length; i++) {
            iterSwapPool = uniV3factory.getPool(_targetToken, config.intermediaryAsset, config.feeTiers[i]);

            // set initial value
            if (bestSwapPool == address(0) && iterSwapPool != address(0)) {
                swapFee = config.feeTiers[i];
                bestSwapPool = iterSwapPool;
            }

            if (
                iterSwapPool != address(0)
                    && IUniswapV3Pool(bestSwapPool).liquidity() < IUniswapV3Pool(iterSwapPool).liquidity()
            ) {
                swapFee = config.feeTiers[i];
                bestSwapPool = iterSwapPool;
            }
        }
    }

    /**
     * @notice Internal function to access the config storage.
     * @return config The config storage instance.
     */
    function _configStorage() internal pure returns (Config storage config) {
        bytes32 slot = CONFIG_SLOT;
        assembly {
            config.slot := slot
        }
    }
}


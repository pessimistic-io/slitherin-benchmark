// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// imported contracts and libraries
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

// interfaces
import "./ILiquidityDex.sol";
import "./ISwapRouter.sol";

// libraries
import "./Addresses.sol";

// constants and types
import {UniswapV3DexStorage} from "./UniswapV3Dex.sol";

contract UniV3Dex is Ownable, ILiquidityDex, UniswapV3DexStorage {
    using SafeERC20 for IERC20;

    function doSwap(
        uint256 _sellAmount,
        uint256 _minBuyAmount,
        address _receiver,
        address[] memory _path
    ) external override returns (uint256) {
        address sellToken = _path[0];

        IERC20(sellToken).safeIncreaseAllowance(
            Addresses.uniswapV3Router,
            _sellAmount
        );

        bytes memory encodedPath = abi.encodePacked(sellToken);
        for (uint256 idx = 1; idx < _path.length; ) {
            encodedPath = abi.encodePacked(
                encodedPath,
                pairFee(_path[idx - 1], _path[idx]),
                _path[idx]
            );
            unchecked {
                ++idx;
            }
        }

        ISwapRouter.ExactInputParams memory param = ISwapRouter
            .ExactInputParams({
                path: encodedPath,
                recipient: _receiver,
                deadline: block.timestamp,
                amountIn: _sellAmount,
                amountOutMinimum: _minBuyAmount
            });

        return ISwapRouter(Addresses.uniswapV3Router).exactInput(param);
    }

    function pairFee(
        address _sellToken,
        address _buyToken
    ) public view returns (uint24 fee) {
        if (_pairFee[_sellToken][_buyToken] != 0) {
            return _pairFee[_sellToken][_buyToken];
        } else {
            return 500;
        }
    }

    function setFee(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyOwner {
        _pairFee[_token0][_token1] = _fee;
        _pairFee[_token1][_token0] = _fee;
    }

    receive() external payable {}
}


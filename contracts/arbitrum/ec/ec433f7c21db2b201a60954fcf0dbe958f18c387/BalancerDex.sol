// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// imported contracts and libraries
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

// interfaces
import "./ILiquidityDex.sol";
import "./IBVault.sol";

// libraries
import "./Addresses.sol";

// constants and types
import {BalancerDexStorage} from "./storage_BalancerDex.sol";

contract BalancerDex is Ownable, ILiquidityDex, BalancerDexStorage {
    using SafeERC20 for IERC20;

    function doSwap(
        uint256 _sellAmount,
        uint256 _minBuyAmount,
        address _receiver,
        address[] memory _path
    ) external override returns (uint256) {
        address sellToken = _path[0];
        address buyToken = _path[_path.length - 1];

        bytes32[] memory poolId = _poolIds[sellToken][buyToken];

        IBVault.BatchSwapStep[] memory swaps = new IBVault.BatchSwapStep[](
            _path.length - 1
        );

        swaps[0].amount = _sellAmount;
        for (uint256 idx; idx < _path.length - 1; ) {
            swaps[idx].poolId = poolId[idx];
            swaps[idx].assetInIndex = idx;
            swaps[idx].assetOutIndex = idx + 1;

            unchecked {
                ++idx;
            }
        }

        IAsset[] memory assets = new IAsset[](_path.length);
        for (uint256 idx; idx < _path.length; ) {
            assets[idx] = IAsset(_path[idx]);

            unchecked {
                ++idx;
            }
        }

        IBVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.recipient = payable(_receiver);

        int256[] memory limits = new int256[](_path.length);
        limits[0] = int256(_sellAmount);
        limits[_path.length - 1] = -int256(_minBuyAmount);

        IERC20(sellToken).safeIncreaseAllowance(
            Addresses.balancerVault,
            _sellAmount
        );

        return
            uint256(
                IBVault(Addresses.balancerVault).batchSwap(
                    IBVault.SwapKind.GIVEN_IN,
                    swaps,
                    assets,
                    funds,
                    limits,
                    block.timestamp
                )[0]
            );
    }

    function setPool(
        address _token0,
        address _token1,
        bytes32[] memory _poolId
    ) external onlyOwner {
        _poolIds[_token0][_token1] = _poolId;
        _poolIds[_token1][_token0] = _poolId;
    }

    function pool(
        address _token0,
        address _token1
    ) public view returns (bytes32[] memory) {
        return _poolIds[_token0][_token1];
    }

    receive() external payable {}
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IUniswapRouterV3WithDeadline.sol";
import "./DestSwapper.sol";

// Swaps rewards with UniV3
contract DestSwapperUniV3 is DestSwapper {
    using SafeERC20 for IERC20;

    address public unirouter;
    bytes public rewardToNativePath;

    function initialize(
        address[] memory _destSwapperAddresses,
        address _endpoint,
        uint256 _srcPoolId,
        address _unirouter,
        bytes memory _rewardToNativePath
    ) public initializer {
        __DestSwapper_init(_destSwapperAddresses, _endpoint, _srcPoolId);
        unirouter = _unirouter;
        rewardToNativePath = _rewardToNativePath;

        IERC20(reward).approve(unirouter, type(uint).max);
    }

    function _swap(uint256 _amount) internal override returns (uint256 nativeAmount) {
        uint256 before = IERC20(native).balanceOf(address(this));
        _swapUniV3(_amount);
        return IERC20(native).balanceOf(address(this)) - before;
    }

    function _swapUniV3(uint256 _amount) internal {
        IUniswapRouterV3WithDeadline.ExactInputParams memory params = IUniswapRouterV3WithDeadline.ExactInputParams({
            path: rewardToNativePath,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amount,
            amountOutMinimum: 0
        });
        IUniswapRouterV3WithDeadline(unirouter).exactInput(params);
    }

    function setRoute(address[] calldata _route, uint24[] calldata _fees) external onlyOwner {
        bytes memory path = abi.encodePacked(_route[0]);
        uint256 feeLength = _fees.length;
        for (uint256 i = 0; i < feeLength; i++) {
            path = abi.encodePacked(path, _fees[i], _route[i+1]);
        }
        rewardToNativePath = path;
    }
}


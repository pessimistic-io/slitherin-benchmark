pragma solidity 0.5.16;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";

/// @title Swapping library
/// @author Chainvisions
/// @notice Library for performing swaps on dexes.

contract SwappingLibrary {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    function _swap(
        address _router,
        address _tokenFrom,
        uint256 _amount,
        address[] memory _routes
    ) internal returns (uint256 endAmount) {
        IERC20(_tokenFrom).safeApprove(_router, 0);
        IERC20(_tokenFrom).safeApprove(_router, _amount);
        uint256[] memory amounts = IUniswapV2Router02(_router).swapExactTokensForTokens(_amount, 0, _routes, address(this), block.timestamp.add(600));
        endAmount = amounts[amounts.length.sub(1)];
    }

    function _crossSwap(
        address[] memory _routers,
        address _tokenFrom,
        uint256 _amount,
        address[] memory _route
    ) internal returns (uint256 endAmount) {
        for(uint256 i = 0; i < _routers.length; i++) {
            // Fetch target swap parameters.
            address targetRouter = _routers[i];
            address[] memory targetRoute = new address[](2);

            // Push target route.
            targetRoute[0] = _route[i];
            targetRoute[1] = _route[i+1];

            // Fetch conversion token and amount to swap.
            address conversionToken = targetRoute[0];
            uint256 conversionBalance;
            if(conversionToken == _tokenFrom) {
                conversionBalance = _amount;
            } else {
                conversionBalance = IERC20(conversionToken).balanceOf(address(this));
            }

            // Perform swap.
            if(targetRoute[1] != _route[_route.length - 1]) {
                _swap(targetRouter, conversionToken, conversionBalance, targetRoute);
            } else {
                endAmount = _swap(targetRouter, conversionToken, conversionBalance, targetRoute);
            }
        }
    }
}

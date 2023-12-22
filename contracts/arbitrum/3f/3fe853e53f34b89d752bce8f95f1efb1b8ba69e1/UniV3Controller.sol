// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./ISwapRouter.sol";
import "./ISwapController.sol";


contract UniV3Controller is ISwapController {
    using SafeERC20 for IERC20;



    address public router;
    address public gov;
    mapping(address => bytes) public paths;


    constructor(address _router) public {
        router = _router;
        gov = msg.sender;
    }
    modifier onlyGov() {
        require(msg.sender == gov, "FeeController: forbidden");
        _;
    }
    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setPathsRoutes(
        address _token,
        bytes calldata _routes
    ) external onlyGov {
        paths[_token] = _routes;
    }


    function swapExactInputMultiHop(
        bytes memory path,
        address tokenIn,
        uint amountIn,
        uint256 amountOutMinimum,
        address to
    ) public returns (uint amountOut) {
        IERC20(tokenIn).approve(router, amountIn);
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
        path : path,
        recipient : to,
        deadline : block.timestamp,
        amountIn : amountIn,
        amountOutMinimum : amountOutMinimum
        });
        amountOut = ISwapRouter(router).exactInput(params);
    }

    function swap(address tokenIn, uint256 amount, uint256 minAmount, address to) override external {
        bytes memory path = paths[tokenIn];
        swapExactInputMultiHop(path, tokenIn, amount, minAmount, to);
    }


    function governanceRecoverUnsupported(IERC20 _token) external onlyGov {
        _token.transfer(gov, _token.balanceOf(address(this)));
    }
}


// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ERC20_IERC20.sol";
import "./IDeployment.sol";
import "./IDeploymentManager.sol";
import "./ITreasury.sol";
import "./IUniswapV2Router.sol";
import "./UmamiAccessControlled.sol";


abstract contract Deployment is IDeployment, UmamiAccessControlled {
    using SafeERC20 for IERC20;

    ITreasury public immutable treasury;
    uint256 public constant SCALE = 1000;
    address public immutable sushiRouter;
    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event Harvest(bool dumpToken);
    event HarvestReward(address token, uint256 amount);
    event Compound();
    event SwapToken(address inputToken, uint256 inputAmount, address outputToken, uint256 outputAmount);

    constructor (
            IDeploymentManager manager, 
            ITreasury _treasury,
            address _sushiRouter
        ) UmamiAccessControlled(manager) {
        treasury = _treasury;
        sushiRouter = _sushiRouter;
    }

    function swapToken(address[] memory path, uint256 amount, uint256 minOutputAmount) internal returns (uint256) {
        if (minOutputAmount == 0) {
            uint256[] memory amountsOut = IUniswapV2Router(sushiRouter).getAmountsOut(amount, path);
            minOutputAmount = amountsOut[amountsOut.length - 1];
        }
        IERC20(path[0]).approve(sushiRouter, amount);
        uint256[] memory withdrawAmounts = IUniswapV2Router(sushiRouter).swapExactTokensForTokens(
            amount,
            minOutputAmount,
            path,
            address(this),
            block.timestamp
        );
        uint256 outputAmount = withdrawAmounts[path.length - 1];
        emit SwapToken(path[0], amount, path[path.length - 1], outputAmount);
        return outputAmount;
    }

    function getSlippageAdjustedAmount(uint256 amount, uint256 slippage) internal pure returns (uint256) {
        return (amount * (1*SCALE - slippage)) / SCALE;
    }

    function distributeToken(address token, uint256 amount) internal {
        address dest = deploymentManager.getRewardDestination();
        IERC20(token).safeTransfer(dest, amount);
    }

    function rescueToken(address token) external override onlyManager {
        IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function rescueETH() external override onlyManager {
        payable(msg.sender).transfer(address(this).balance);
    }

    function rescueCall(address target, string calldata signature, bytes calldata parameters) external override onlyManager returns(bytes memory) {
        (bool success, bytes memory data) = target.call(
            abi.encodePacked(bytes4(keccak256(bytes(signature))), parameters)
        );
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
        return data;
    }

}



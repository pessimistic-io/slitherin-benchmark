//SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./ICapUSDCReward.sol";
import "./IWETH9.sol";
import {Ownable} from "./Ownable.sol";
import {Pausable} from "./Pausable.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {TransferHelper} from "./TransferHelper.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

contract CapStrategy is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                                 Constants
    //////////////////////////////////////////////////////////////*/

    ISwapRouter public constant swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant yieldDistributor =
        0xfC22DAfae9ef61535019Df250E1f60A21c3fAD8b;

    /*///////////////////////////////////////////////////////////////
                                 State Variables
    //////////////////////////////////////////////////////////////*/

    ICapStrategy public cap;
    ICapUSDCReward public usdcReward;
    uint256 public claimed;
    uint24 poolFee;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event Migrated(
        address indexed _caller,
        address indexed _recipient,
        uint256 _amount
    );
    event RewardClaimed(
        address indexed _caller,
        uint256 _reward,
        uint256 _swapReturnInWETH
    );
    event YieldTransfered(address indexed _caller, uint256 _yield);
    event Withdrawal(address indexed _caller, uint256 _amount);
    event Deposited(address indexed _caller, uint256 _amount);

    /*///////////////////////////////////////////////////////////////
                                 Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _cap, address _usdcReward) {
        cap = ICapStrategy(_cap);
        usdcReward = ICapUSDCReward(_usdcReward);
    }

    /*///////////////////////////////////////////////////////////////
                                 User Functions
    //////////////////////////////////////////////////////////////*/

    function depositUSDC(uint256 amount) external whenNotPaused {
        require(amount > 0, "Must be more than 0");
        IERC20(USDC).safeIncreaseAllowance(address(cap), amount);
        cap.deposit(amount);
        emit Deposited(msg.sender, amount);
    }

    function claimUSDCRewards() external {
        uint256 currentBalance = IERC20(USDC).balanceOf(address(this));
        ICapUSDCReward(usdcReward).collectReward();
        uint256 _claimed = IERC20(USDC).balanceOf(address(this)) -
            currentBalance;
        claimed = _claimed;
    }

    function transferYield() external {
        uint256 amount = IERC20(WETH).balanceOf(address(this));
        require(amount > 0, "Zero WETH");
        IERC20(WETH).safeTransfer(yieldDistributor, amount);
        emit YieldTransfered(msg.sender, amount);
    }

    /*///////////////////////////////////////////////////////////////
                                 Admin Functions
    //////////////////////////////////////////////////////////////*/

    function withdrawUSDC(uint256 _amount) external onlyOwner {
        cap.withdraw(_amount);
        emit Withdrawal(msg.sender, _amount);
    }

    function migrate(address _to) external onlyOwner {
        require(_to != address(0), "To != Zero Address");
        uint256 amount = IERC20(USDC).balanceOf(address(this));
        IERC20(USDC).safeTransfer(_to, amount);
        emit Migrated(msg.sender, _to, amount);
    }

    function wethCall(uint256 amount) external payable onlyOwner {
        IWETH9(WETH).deposit{value: amount}();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setPoolFee(uint24 _fee) external onlyOwner {
        poolFee = _fee;
    }

    function swap(uint256 _minAmount) external onlyOwner returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: WETH,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: claimed,
                amountOutMinimum: _minAmount,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        return amountOut;
    }

    receive() external payable {}
}


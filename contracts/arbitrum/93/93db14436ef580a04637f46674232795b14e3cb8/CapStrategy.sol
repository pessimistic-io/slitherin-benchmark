//SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./ICapUSDCReward.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {OracleLibrary} from "./OracleLibrary.sol";
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
    address public constant FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    /*///////////////////////////////////////////////////////////////
                                 State Variables
    //////////////////////////////////////////////////////////////*/

    uint256 public claimed;
    ICapStrategy public cap;
    ICapUSDCReward public usdcReward;
    address public immutable pool;

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

        address _pool = IUniswapV3Factory(FACTORY).getPool(USDC, WETH, 500);
        require(_pool != address(0), "pool doesn't exist");

        pool = _pool;
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
        usdcReward.collectReward();
        uint256 claimed = IERC20(USDC).balanceOf(address(this)) -
            currentBalance;
        IERC20(USDC).safeIncreaseAllowance(address(swapRouter), claimed);
        uint256 amountSwapped = swap();
        emit RewardClaimed(msg.sender, claimed, amountSwapped);
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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /*///////////////////////////////////////////////////////////////
                                 View Functions
    //////////////////////////////////////////////////////////////*/

    function checkReward() public view returns (uint256) {
        uint256 amount = checkClaimableReward();
        return amount;
    }

    function checkClaimableReward() internal view returns (uint256) {
        uint256 amount = usdcReward.getClaimableReward();
        return amount;
    }

    /*///////////////////////////////////////////////////////////////
                                 Internal Functions
    //////////////////////////////////////////////////////////////*/

    function swap() internal returns (uint256) {
        uint256 minAmount = estimateAmountOut(uint128(claimed), 30);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: WETH,
                fee: 500,
                recipient: yieldDistributor,
                deadline: block.timestamp,
                amountIn: claimed,
                amountOutMinimum: minAmount,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        IERC20(WETH).safeTransfer(yieldDistributor, amountOut);
        emit YieldTransfered(msg.sender, amountOut);
        return amountOut;
    }

    function estimateAmountOut(uint128 amountIn, uint32 secondsAgo)
        internal
        view
        returns (uint256 amountOut)
    {
        (int24 tick, ) = OracleLibrary.consult(pool, secondsAgo);

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, USDC, WETH);
        amountOut = (amountOut * 985) / 1000;
    }
}


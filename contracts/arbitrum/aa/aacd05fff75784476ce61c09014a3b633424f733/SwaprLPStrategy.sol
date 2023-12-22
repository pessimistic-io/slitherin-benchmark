// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.16;

import "./Math.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IStrategy.sol";
import "./IVault.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";
import "./BaseUpgradeableStrategy.sol";
import "./IStakeReward.sol";

/// @title Swapr LP Strategy 
/// @author Chainvisions + customization by jlontele
/// @notice Strategy for Swapr LPs

contract SwaprLPStrategy is BaseUpgradeableStrategy {
    using SafeERC20 for IERC20;

    address public constant DXswapRouter = address(0x530476d5583724A89c8841eB6Da76E7Af4C0F17E);
    mapping(address => address[]) public routes;

    constructor() BaseUpgradeableStrategy() public {}

    function __Strategy_init(
        address _storage,
        address _underlying,
        address _vault,
        address _stakingContract,
        address _rewardToken
    )
    public initializer {
        BaseUpgradeableStrategy.initialize(
            _storage,
            _underlying,
            _vault,
            _stakingContract,
            _rewardToken,
            true,
            1e16,
            12 hours
        );
    }

    /*
    * Harvests yields generated and reinvests into the underlying. This
    * function call will fail if deposits are paused.
    */
    function doHardWork() external onlyNotPausedInvesting restricted {
        IStakeReward(rewardPool()).claimAll(address(this));
        _liquidateReward();
        _investAllUnderlying();
    }

    /*
    * Transfers out tokens that the contract is holding. One thing to note
    * is that this contract exposes a list of tokens that cannot be salvaged. 
    * This is to ensure that a malicious admin cannot steal from the vault users.
    */
    function salvage(address recipient, address token, uint256 amount) external restricted {
        require(!unsalvagableTokens(token), "Strategy: Unsalvagable token");
        IERC20(token).transfer(recipient, amount);
    }

    function finalizeUpgrade() external onlyGovernance {
        _finalizeUpgrade();
    }

    /*
    * Current amount of underlying invested.
    */
    function investedUnderlyingBalance() external view returns (uint256) {
        if (rewardPool() == address(0)) {
            return IERC20(underlying()).balanceOf(address(this));
        }
        return (_rewardPoolStake() + IERC20(underlying()).balanceOf(address(this)));
    }

    /*
    * Withdraws all of the underlying to the vault. This is used in the case
    * of a problem with the strategy or a bug that compromises the safety of the
    * vault's users.
    */
    function withdrawAllToVault() public restricted {
        if(rewardPool() != address(0)) {
            IStakeReward(rewardPool()).exit(address(this)); 
        }
        _liquidateReward();
        IERC20(underlying()).safeTransfer(vault(), IERC20(underlying()).balanceOf(address(this)));
    }

    /*
    * Withdraws `amount` of the underlying to the vault.
    */
    function withdrawToVault(uint256 amount) public restricted {
        // Typically there wouldn't be any amount here
        // however, it is possible because of the emergencyExit
        if(amount > IERC20(underlying()).balanceOf(address(this))){
            // While we have the check above, we still using SafeMath below
            // for the peace of mind (in case something gets changed in between)
            uint256 needToWithdraw = (amount - IERC20(underlying()).balanceOf(address(this)));
            IStakeReward(rewardPool()).claimAll(address(this));
            IStakeReward(rewardPool()).withdraw(Math.min(_rewardPoolStake(), needToWithdraw));
        }

        IERC20(underlying()).safeTransfer(vault(), amount);
    }

    /*
    * Performs an emergency exit from the farming contract and
    * pauses the strategy.
    */
    function emergencyExit() public onlyGovernance {
        IStakeReward(rewardPool()).exit(address(this));
        _setPausedInvesting(true);
    }

    /*
    * Re-enables investing into the strategy contract.
    */
    function continueInvesting() public onlyGovernance {
        _setPausedInvesting(false);
    }

    function setSell(bool _sell) public onlyGovernance {
        _setSell(_sell);
    }

    function setSellFloor(uint256 _sellFloor) public onlyGovernance {
        _setSellFloor(_sellFloor);
    }

    function depositArbCheck() public pure returns (bool) {
        return true;
    }

    function unsalvagableTokens(address token) public view returns (bool) {
        return (token == underlying() || token == rewardToken());
    }

    function _investAllUnderlying() internal onlyNotPausedInvesting {
        uint256 underlyingBalance = IERC20(underlying()).balanceOf(address(this));
        if(underlyingBalance > 0) {
            IERC20(underlying()).safeApprove(rewardPool(), 0);
            IERC20(underlying()).safeApprove(rewardPool(), underlyingBalance);
            IStakeReward(rewardPool()).stake(underlyingBalance);
        }
    }

    /*
    * Liquidates the reward and collects fees for BELUGA stakers.
    */
    function _liquidateReward() internal {
        uint256 rewardBalance = IERC20(rewardToken()).balanceOf(address(this));
        if(!sell() || rewardBalance < sellFloor()) {
            emit ProfitsNotCollected(sell(), rewardBalance < sellFloor());
            return;
        }

        notifyProfitInRewardToken(rewardBalance);

        rewardBalance = IERC20(rewardToken()).balanceOf(address(this));

        address token0 = IUniswapV2Pair(underlying()).token0();
        address token1 = IUniswapV2Pair(underlying()).token1();

        uint256 toToken0 = (rewardBalance / 2);
        uint256 toToken1 = (rewardBalance - toToken0);

        uint256 token0Amount;
        uint256 token1Amount;

        if(routes[token0].length > 1) {
            IERC20(rewardToken()).safeApprove(DXswapRouter, 0);
            IERC20(rewardToken()).safeApprove(DXswapRouter, toToken0);
            uint256[] memory amounts = IUniswapV2Router02(DXswapRouter).swapExactTokensForTokens(toToken0, 0, routes[token0], address(this), (block.timestamp + 600));
            token0Amount = amounts[(amounts.length - 1)];
        } else {
            token0Amount = toToken0;
        }

        if(routes[token1].length > 1) {
            IERC20(rewardToken()).safeApprove(DXswapRouter, 0);
            IERC20(rewardToken()).safeApprove(DXswapRouter, toToken1);
            uint256[] memory amounts = IUniswapV2Router02(DXswapRouter).swapExactTokensForTokens(toToken1, 0, routes[token1], address(this), (block.timestamp + 600));
            token1Amount = amounts[(amounts.length - 1)];
        } else {
            token1Amount = toToken1;
        }

        IERC20(token0).safeApprove(DXswapRouter, 0);
        IERC20(token0).safeApprove(DXswapRouter, token0Amount);

        IERC20(token1).safeApprove(DXswapRouter, 0);
        IERC20(token1).safeApprove(DXswapRouter, token1Amount);

        IUniswapV2Router02(DXswapRouter).addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, address(this), (block.timestamp + 600));
    }

    function _rewardPoolStake() internal view returns (uint256 stake) {
        stake = IStakeReward(rewardPool()).stakedTokensOf(address(this));
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IERC4626.sol";
import "./ERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IWrappedStakedJonesToken.sol";

import "./IJonesDaoAdapter.sol";
import "./IJonesDaoVaultRouter.sol";
import "./IMiniChefV2.sol";
import "./IJGLPViewer.sol";

import {TokenUtils} from "./TokenUtils.sol";
import "./Checker.sol";

contract WrappedStakedJonesToken is
    IWrappedStakedJonesToken,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable
{
    mapping(address => bool) private isAllowlisted;

    /// @notice The number of basis points there are to represent exactly 100%.
    uint256 public constant BPS = 1e18;

    address public override token; // jUSDC
    address public override baseToken;
    address public glpAdapter;
    address public glpVaultRouter;
    address public glpStableVault;
    address public jGLPViewer;
    address public stipArbRewarder;
    address public override rewardToken; // staking reward
    uint256 public override stakePoolId;
    uint256 public MINICHEF_ACC_SUSHI_PRECISION;

    uint256 public baseTokenDecimals;
    uint8 public tokenDecimals;

    uint256 public curAccumulatedRewardPerShare;
    // account address => snapshotAccumulatedRewardPerShare
    mapping(address => uint256) public accounts;

    event RewardsClaimed(address indexed account, uint256 rewardsClaimed);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _glpAdapter,
        address _jGLPViewer,
        address _stipArbRewarder,
        uint256 _pid,
        uint256 _sushiPrecision,
        string memory _name,
        string memory _symbol
    ) public initializer {
        Checker.checkArgument(_glpAdapter != address(0), "wrong token");

        glpAdapter = _glpAdapter;
        glpVaultRouter = IJonesDaoAdapter(_glpAdapter).vaultRouter();
        glpStableVault = IJonesDaoAdapter(_glpAdapter).stableVault();
        jGLPViewer = _jGLPViewer;
        stipArbRewarder = _stipArbRewarder;
        rewardToken = IMiniChefV2(stipArbRewarder).SUSHI();
        stakePoolId = _pid;
        MINICHEF_ACC_SUSHI_PRECISION = _sushiPrecision;

        baseToken = IERC4626(glpStableVault).asset();
        token = IJonesDaoVaultRouter(glpVaultRouter).rewardCompounder(
            baseToken
        );

        baseTokenDecimals = TokenUtils.expectDecimals(baseToken);
        tokenDecimals = TokenUtils.expectDecimals(token);
        __ERC20_init(_name, _symbol);
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function price() external view override returns (uint256) {
        (uint256 usdcRedemption, ) = IJGLPViewer(jGLPViewer).getUSDCRedemption(
            1e18,
            address(this)
        );
        return
            usdcRedemption -
            ((usdcRedemption *
                (IMiniChefV2(stipArbRewarder).poolInfo(stakePoolId))
                    .depositIncentives) / MINICHEF_ACC_SUSHI_PRECISION);
    }

    function claim() external override nonReentrant returns (uint256) {
        return _claim(msg.sender);
    }

    function deposit(
        uint256 amount,
        address recipient
    ) external override nonReentrant returns (uint256) {
        amount = TokenUtils.safeTransferFrom(
            baseToken,
            msg.sender,
            address(this),
            amount
        );
        Checker.checkArgument(amount > 0, "zero wrap amount");

        _harvest();
        _claim(recipient);

        uint256 depositedAmount = _deposit(amount);
        uint256 stakedAmount = _stake(depositedAmount);
        _mint(recipient, stakedAmount);
        return stakedAmount;
    }

    function withdraw(
        uint256 amount,
        address recipient
    ) external override nonReentrant returns (uint256) {
        Checker.checkArgument(amount > 0, "zero unwrap amount");
        _harvest();
        _claim(recipient);

        _burn(msg.sender, amount);
        uint256 amountUnstaked = _unstake(amount);
        uint256 amountWithdrawn = _withdraw(amountUnstaked, recipient);
        return amountWithdrawn;
    }

    function _deposit(uint256 amount) internal returns (uint256) {
        TokenUtils.safeApprove(baseToken, glpAdapter, amount);
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IJonesDaoAdapter(glpAdapter).depositStable(amount, true);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 receivedAmount = balanceAfter - balanceBefore;
        require(receivedAmount > 0, "no token received");
        return receivedAmount;
    }

    function _stake(uint256 amount) internal returns (uint256) {
        TokenUtils.safeApprove(token, stipArbRewarder, amount);
        uint256 stakedBalanceBefore = _balanceOfStakedToken();
        IMiniChefV2(stipArbRewarder).deposit(
            stakePoolId,
            amount,
            address(this)
        );
        uint256 stakedBalanceAfter = _balanceOfStakedToken();
        return stakedBalanceAfter - stakedBalanceBefore;
    }

    function _withdraw(
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        uint256 balanceBefore = _balanceOfBaseToken();
        IJonesDaoVaultRouter(glpVaultRouter).stableWithdrawalSignal(
            amount,
            true
        );
        uint256 balanceAfter = _balanceOfBaseToken();
        uint256 receivedAmount = balanceAfter - balanceBefore;
        require(receivedAmount > 0, "no baseToken withdrawn");
        TokenUtils.safeTransfer(baseToken, recipient, receivedAmount);
        return receivedAmount;
    }

    function _unstake(uint256 amount) internal returns (uint256) {
        uint256 yieldBalanceBefore = _balanceOfYieldToken();
        IMiniChefV2(stipArbRewarder).withdraw(
            stakePoolId,
            amount,
            address(this)
        );
        uint256 yieldBalanceAfter = _balanceOfYieldToken();
        Checker.checkState(
            yieldBalanceAfter - yieldBalanceBefore == amount,
            "unstake failed"
        );
        return yieldBalanceAfter - yieldBalanceBefore;
    }

    function _harvest() internal returns (uint256 harvestedRewardAmount) {
        if (totalSupply() == 0) return 0;
        harvestedRewardAmount = _balanceOfRewardToken();
        IMiniChefV2(stipArbRewarder).harvest(stakePoolId, address(this));
        harvestedRewardAmount = _balanceOfRewardToken() - harvestedRewardAmount;

        curAccumulatedRewardPerShare += ((harvestedRewardAmount * BPS) /
            totalSupply());
    }

    function _claim(address recipient) internal returns (uint256) {
        uint256 claimableRewardsPerShare = curAccumulatedRewardPerShare -
            accounts[recipient];
        uint256 rewardsClaimable = (claimableRewardsPerShare *
            balanceOf(recipient)) / BPS;
        accounts[recipient] = curAccumulatedRewardPerShare;
        TokenUtils.safeTransfer(rewardToken, recipient, rewardsClaimable);
        emit RewardsClaimed(recipient, rewardsClaimable);
        return rewardsClaimable;
    }

    function _balanceOfRewardToken() internal view returns (uint256) {
        return TokenUtils.safeBalanceOf(rewardToken, address(this));
    }

    function _balanceOfYieldToken() internal view returns (uint256) {
        return TokenUtils.safeBalanceOf(token, address(this));
    }

    function _balanceOfBaseToken() internal view returns (uint256) {
        return TokenUtils.safeBalanceOf(baseToken, address(this));
    }

    function _balanceOfStakedToken() internal returns (uint256) {
        return
            (IMiniChefV2(stipArbRewarder).userInfo(stakePoolId, address(this)))
                .amount;
    }

    uint256[100] private __gap;
}


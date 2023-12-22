// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
//import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./Ownable.sol";
//import "@openzeppelin/contracts/utils/Pausable.sol";

import "./IBalancerVault.sol";
import "./IRewardsGauge.sol";
import "./StratManager.sol";
import "./FeeManager.sol";

//import "../../utils/GasThrottler.sol";

contract StrategyBalancerMultiRewardGauge is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    //using SafeMath for uint256;

    /**
     *@notice Tokens used
     */
    address public want;
    address public output = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address public native = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address public input;
    address[] public lpTokens;

    /**
     *@notice Reward
     *@param token token
     *@param rewardSwapPoolId rewards swap pool id
     *@param minAmount minimum amount to be swapped to native
     */
    struct Reward {
        address token;
        bytes32 rewardSwapPoolId;
        uint minAmount;
    }

    Reward[] public rewards;

    /**
     *@notice Third party contracts
     */
    address public rewardsGauge;

    bytes32 public wantPoolId;
    bytes32 public nativeSwapPoolId;
    bytes32 public inputSwapPoolId;

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(
        address indexed harvester,
        uint256 wantHarvested,
        uint256 tvl
    );
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    /**
     * @dev Initializes strategy.
     * @param _balancerPoolIds Balancer pool id
     * @param _rewardsGauge rewards gauge
     * @param _input input
     * @param _vault vault address
     * @param _unirouter unirouter address
     * @param _keeper keepers address
     * @param _beefyFeeRecipient  beefy fee recipient address
     */
    constructor(
        bytes32[] memory _balancerPoolIds,
        address _rewardsGauge,
        address _input,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    )
        StratManager(
            _keeper,
            _strategist,
            _unirouter,
            _vault,
            _beefyFeeRecipient
        )
    {
        wantPoolId = _balancerPoolIds[0];
        nativeSwapPoolId = _balancerPoolIds[1];
        inputSwapPoolId = _balancerPoolIds[2];
        rewardsGauge = _rewardsGauge;

        (want, ) = IBalancerVault(unirouter).getPool(wantPoolId);
        input = _input;

        (lpTokens, , ) = IBalancerVault(unirouter).getPoolTokens(wantPoolId);
        swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        funds = IBalancerVault.FundManagement(
            address(this),
            false,
            payable(address(this)),
            false
        );

        _giveAllowances();
    }

    /**
     *@notice Puts the funds to work
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardsGauge(rewardsGauge).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    /**
     *@notice Withdraw for amount
     *@param _amount Withdraw amount
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IRewardsGauge(rewardsGauge).withdraw(_amount - wantBal);

            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) /
                WITHDRAWAL_MAX;

            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    /**
     *@notice Harvest on deposit check
     */
    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    /**
     *@notice harvests rewards
     */
    function harvest() external virtual {
        _harvest(tx.origin);
    }

    /**
     *@notice harvests rewards
     *@param callFeeRecipient fee recipient address
     */
    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    /**
     *@notice harvests rewards manager only
     */
    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    /**
     *@notice compounds earnings and charges performance fee
     *@param callFeeRecipient Caller address
     */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IRewardsGauge(rewardsGauge).claim_rewards(address(this));
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    /**
     *@notice Swap rewards to Native
     */
    function swapRewardsToNative() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            balancerSwap(nativeSwapPoolId, output, native, outputBal);
        }

        /**
         *@notice extras
         */
        for (uint i; i < rewards.length; i++) {
            uint bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                balancerSwap(
                    rewards[i].rewardSwapPoolId,
                    rewards[i].token,
                    native,
                    bal
                );
            }
        }
    }

    /**
     *@notice Performance fees
     *@param callFeeRecipient Caller address
     */
    function chargeFees(address callFeeRecipient) internal {
        uint256 nativeBal = (IERC20(native).balanceOf(address(this)) * 45) /
            1000;

        uint256 callFeeAmount = (nativeBal * callFee) / MAX_FEE;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = (nativeBal * beefyFee) / MAX_FEE;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = (nativeBal * STRATEGIST_FEE) / MAX_FEE;
        IERC20(native).safeTransfer(strategist, strategistFee);
    }

    /**
     *@notice Adds liquidity to AMM and gets more LP tokens.
     */
    function addLiquidity() internal {
        if (input != native) {
            uint256 nativeBal = IERC20(native).balanceOf(address(this));
            balancerSwap(inputSwapPoolId, native, input, nativeBal);
        }

        uint256 inputBal = IERC20(input).balanceOf(address(this));
        balancerJoin(wantPoolId, input, inputBal);
    }

    /**
     *@notice Balancer swap
     *@param _poolId Pool ID
     *@param _tokenIn Token in
     *@param _tokenOut Token out
     *@param _amountIn Amount to swap
     */
    function balancerSwap(
        bytes32 _poolId,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(
            _poolId,
            swapKind,
            _tokenIn,
            _tokenOut,
            _amountIn,
            ""
        );
        return
            IBalancerVault(unirouter).swap(
                singleSwap,
                funds,
                1,
                block.timestamp
            );
    }

    /**
     *@notice Balancer join
     *@param _poolId Pool ID
     *@param _tokenIn Token in
     *@param _amountIn Amount In
     */
    function balancerJoin(
        bytes32 _poolId,
        address _tokenIn,
        uint256 _amountIn
    ) internal {
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = lpTokens[i] == _tokenIn ? _amountIn : 0;
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault
            .JoinPoolRequest(lpTokens, amounts, userData, false);
        IBalancerVault(unirouter).joinPool(
            _poolId,
            address(this),
            address(this),
            request
        );
    }

    /**
     *@notice Calculate the total underlaying 'want' held by the strat.
     *@return uint256 balance
     */
    function balanceOf() public view returns (uint256) {
        //return balanceOfWant().add(balanceOfPool());
        return balanceOfWant() + balanceOfPool();
    }

    /**
     *@notice It calculates how much 'want' this contract holds.
     *@return uint256 Balance
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     *@notice It calculates how much 'want' the strategy has working in the farm.
     *@return uint256 Amount
     */
    function balanceOfPool() public view returns (uint256) {
        return IRewardsGauge(rewardsGauge).balanceOf(address(this));
    }

    /**
     *@notice Rreturns rewards unharvested
     *@return uint256 Claimable rewards amount
     */
    function rewardsAvailable() public view returns (uint256) {
        return
            IRewardsGauge(rewardsGauge).claimable_reward(address(this), output);
    }

    /**
     *@notice Native reward amount for calling harvest
     *@return uint256 Native reward amount
     */
    function callReward() public returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            nativeOut = balancerSwap(
                nativeSwapPoolId,
                output,
                native,
                outputBal
            );
        }

        if (rewards.length != 0) {
            for (uint i; i < rewards.length; ++i) {
                uint256 rewardBal = IERC20(rewards[i].token).balanceOf(
                    address(this)
                );
                if (rewardBal > 0) {
                    nativeOut += balancerSwap(
                        rewards[i].rewardSwapPoolId,
                        rewards[i].token,
                        native,
                        rewardBal
                    );
                }
            }
        }

        return (((nativeOut * 45) / 1000) * callFee) / MAX_FEE;
    }

    /**
     *@notice Add reward token
     *@param _token reward token
     *@param _rewardSwapPoolId Reward swap pool id
     *@param _minAmount minumum amount
     */
    function addRewardToken(
        address _token,
        bytes32 _rewardSwapPoolId,
        uint _minAmount
    ) external onlyOwner {
        require(_token != want, "!want");
        require(_token != native, "!native");

        rewards.push(Reward(_token, _rewardSwapPoolId, _minAmount));
        IERC20(_token).safeApprove(unirouter, 0);
        IERC20(_token).safeApprove(unirouter, type(uint).max);
    }

    /**
     *@notice Reset reward token
     */
    function resetRewardTokens() external onlyManager {
        delete rewards;
    }

    /**
     *@notice Set harvest on deposit true/false
     *@param _harvestOnDeposit true/false
     */
    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    /**
     *@notice Called as part of strat migration. Sends all the available funds back to the vault.
     */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    /**
     *@notice Pauses deposits and withdraws all funds from third party systems.
     */
    function panic() public onlyManager {
        pause();
        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());
    }

    /**
     *@notice pauses the strategy
     */
    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    /**
     *@notice unpauses the strategy
     */
    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    /**
     *@notice Give all allowances
     */
    function _giveAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        if (rewards.length != 0) {
            for (uint i; i < rewards.length; ++i) {
                IERC20(rewards[i].token).safeApprove(unirouter, type(uint).max);
            }
        }

        IERC20(input).safeApprove(unirouter, 0);
        IERC20(input).safeApprove(unirouter, type(uint).max);
    }

    /**
     *@notice Remove all allowances
     */
    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
        if (rewards.length != 0) {
            for (uint i; i < rewards.length; ++i) {
                IERC20(rewards[i].token).safeApprove(unirouter, 0);
            }
        }

        IERC20(input).safeApprove(unirouter, 0);
    }
}


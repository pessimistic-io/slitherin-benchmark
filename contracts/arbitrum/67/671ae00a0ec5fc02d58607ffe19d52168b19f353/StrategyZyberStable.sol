// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";

import "./IUniswapRouterETH.sol";
import "./IUniswapV2Pair.sol";
import "./IWrappedNative.sol";
import "./IStableRouter.sol";
import "./IZyberChef.sol";
import "./StratFeeManager.sol";
import "./GasThrottler.sol";

contract StrategyZyberStable is StratFeeManager, GasThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public input;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public stableRouter;
    uint256 public depositIndex;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToInputRoute;
    address[][] public rewardToOutputRoute;

    event StratHarvest(
        address indexed harvester,
        uint256 wantHarvested,
        uint256 tvl
    );
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(
        uint256 callFees,
        uint256 beefyFees,
        uint256 strategistFees
    );

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _stableRouter,
        CommonAddresses memory _commonAddresses,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToInputRoute
    ) public StratFeeManager(_commonAddresses) {
        want = _want;
        poolId = _poolId;
        chef = _chef;
        stableRouter = _stableRouter;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        input = _outputToInputRoute[_outputToInputRoute.length - 1];
        depositIndex = IStableRouter(stableRouter).getTokenIndex(input);

        outputToNativeRoute = _outputToNativeRoute;
        outputToInputRoute = _outputToInputRoute;

        _giveAllowances();
    }

    /**
     *@notice Puts the funds to work
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IZyberChef(chef).deposit(poolId, wantBal);
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
            IZyberChef(chef).withdraw(poolId, _amount - wantBal);
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
    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    /**
     *@notice harvests rewards
     */
    function harvest() external virtual gasThrottle {
        _harvest(tx.origin);
    }

    /**
     *@notice harvests rewards
     *@param callFeeRecipient fee recipient address
     */
    function harvest(address callFeeRecipient) external virtual gasThrottle {
        _harvest(callFeeRecipient);
    }

    /**
     *@notice harvests rewards manager only
     */
    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    /**
     * @notice Compounds earnings and charges performance fee
     * *@param callFeeRecipient Caller address
     */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IZyberChef(chef).deposit(poolId, 0);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                if (rewardToOutputRoute[i][0] == native) {
                    uint256 nativeBal = address(this).balance;
                    if (nativeBal > 0) {
                        IWrappedNative(native).deposit{value: nativeBal}();
                    }
                }
                uint256 rewardBal = IERC20(rewardToOutputRoute[i][0]).balanceOf(
                    address(this)
                );
                if (rewardBal > 0) {
                    IUniswapRouterETH(unirouter).swapExactTokensForTokens(
                        rewardBal,
                        0,
                        rewardToOutputRoute[i],
                        address(this),
                        block.timestamp
                    );
                }
            }
        }

        uint256 toNative = (IERC20(output).balanceOf(address(this)) *
            fees.total) / DIVISOR;
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(
            toNative,
            0,
            outputToNativeRoute,
            address(this),
            block.timestamp
        );

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = (nativeBal * fees.call) / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = (nativeBal * fees.beefy) / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = (nativeBal * fees.strategist) / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(
            outputBal,
            0,
            outputToInputRoute,
            address(this),
            block.timestamp
        );

        uint256 numberOfTokens = IStableRouter(stableRouter)
            .getNumberOfTokens();
        uint256[] memory inputs = new uint256[](numberOfTokens);
        inputs[depositIndex] = IERC20(input).balanceOf(address(this));
        IStableRouter(stableRouter).addLiquidity(inputs, 1, block.timestamp);
    }

    /**
     *@notice Calculate the total underlaying 'want' held by the strat.
     *@return uint256 balance
     */
    function balanceOf() public view returns (uint256) {
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
        (uint256 _amount, , , ) = IZyberChef(chef).userInfo(
            poolId,
            address(this)
        );
        return _amount;
    }

    /**
     *@notice Rreturns rewards unharvested
     *@return uint256 Amount rewards unharvested
     */
    function rewardsAvailable()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        (address[] memory addresses, , , uint256[] memory amounts) = IZyberChef(
            chef
        ).pendingTokens(poolId, address(this));
        return (addresses, amounts);
    }

    /**
     *@notice Native reward amount for calling harvest
     *@return uint256 Native reward amount
     */
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        (
            address[] memory rewardAdd,
            uint256[] memory rewardBal
        ) = rewardsAvailable();
        uint256 nativeBal;
        try
            IUniswapRouterETH(unirouter).getAmountsOut(
                rewardBal[0],
                outputToNativeRoute
            )
        returns (uint256[] memory amountOut) {
            nativeBal = amountOut[amountOut.length - 1];
        } catch {}

        if (rewardToOutputRoute.length != 0) {
            for (uint256 i; i < rewardToOutputRoute.length; ) {
                for (uint256 j = 1; j < rewardAdd.length; ) {
                    if (rewardAdd[j] == rewardToOutputRoute[i][0]) {
                        try
                            IUniswapRouterETH(unirouter).getAmountsOut(
                                rewardBal[j],
                                rewardToOutputRoute[i]
                            )
                        returns (uint256[] memory initialAmountOut) {
                            uint256 outputBal = initialAmountOut[
                                initialAmountOut.length - 1
                            ];
                            try
                                IUniswapRouterETH(unirouter).getAmountsOut(
                                    outputBal,
                                    outputToNativeRoute
                                )
                            returns (uint256[] memory finalAmountOut) {
                                nativeBal =
                                    nativeBal +
                                    finalAmountOut[finalAmountOut.length - 1];
                            } catch {}
                        } catch {}
                    }
                    unchecked {
                        ++j;
                    }
                }
                unchecked {
                    ++i;
                }
            }
        }

        return (((nativeBal * fees.total) / DIVISOR) * fees.call) / DIVISOR;
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
     *@notice Set should gas throttle true/false
     *@param _shouldGasThrottle true/false
     */
    function setShouldGasThrottle(
        bool _shouldGasThrottle
    ) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    /**
     *@notice Called as part of strat migration. Sends all the available funds back to the vault.
     */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IZyberChef(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    /**
     *@notice Pauses deposits and withdraws all funds from third party systems.
     */
    function panic() public onlyManager {
        pause();
        IZyberChef(chef).emergencyWithdraw(poolId);
    }

    /**
     *@notice pauses strategy
     */
    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    /**
     *@notice unpauses strategy
     */
    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);
        IERC20(input).safeApprove(stableRouter, type(uint256).max);

        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                IERC20(rewardToOutputRoute[i][0]).safeApprove(unirouter, 0);
                IERC20(rewardToOutputRoute[i][0]).safeApprove(
                    unirouter,
                    type(uint256).max
                );
            }
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(input).safeApprove(stableRouter, 0);

        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                IERC20(rewardToOutputRoute[i][0]).safeApprove(unirouter, 0);
            }
        }
    }

    function addRewardRoute(
        address[] memory _rewardToOutputRoute
    ) external onlyOwner {
        IERC20(_rewardToOutputRoute[0]).safeApprove(unirouter, 0);
        IERC20(_rewardToOutputRoute[0]).safeApprove(
            unirouter,
            type(uint256).max
        );
        rewardToOutputRoute.push(_rewardToOutputRoute);
    }

    function removeLastRewardRoute() external onlyManager {
        address reward = rewardToOutputRoute[rewardToOutputRoute.length - 1][0];
        IERC20(reward).safeApprove(unirouter, 0);
        rewardToOutputRoute.pop();
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToInput() external view returns (address[] memory) {
        return outputToInputRoute;
    }

    function rewardToOutput() external view returns (address[][] memory) {
        return rewardToOutputRoute;
    }

    receive() external payable {}
}


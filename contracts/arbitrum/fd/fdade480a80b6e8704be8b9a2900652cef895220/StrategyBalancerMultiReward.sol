// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";

import "./IUniswapRouterETH.sol";
import "./IBalancerVault.sol";
import "./IRewardsGauge.sol";
import "./StratFeeManagerInitializable.sol";
import "./BalancerActionsLib.sol";
import "./BeefyBalancerStructs.sol";
import "./UniV3Actions.sol";

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
}

interface IMinter {
    function mint(address gauge) external;
}

contract StrategyBalancerMultiReward is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public output;
    address public native;

    // Third party contracts
    address public rewardsGauge;

    BeefyBalancerStructs.Input public input;
    BeefyBalancerStructs.BatchSwapStruct[] public nativeToInputRoute;
    BeefyBalancerStructs.BatchSwapStruct[] public outputToNativeRoute;
    address[] public nativeToInputAssets;
    address[] public outputToNativeAssets;

    mapping(address => BeefyBalancerStructs.Reward) public rewards;
    address[] public rewardTokens;

    bool public balSwapOn;

    IBalancerVault.SwapKind public swapKind = IBalancerVault.SwapKind.GIVEN_IN;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        bool _inputIsComposable,
        bool _balSwapOn,
        BeefyBalancerStructs.BatchSwapStruct[] calldata _nativeToInputRoute,
        BeefyBalancerStructs.BatchSwapStruct[] calldata _outputToNativeRoute,
        address[][] calldata _assets,
        address _rewardsGauge,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);

        for (uint i; i < _nativeToInputRoute.length; ++i) {
            nativeToInputRoute.push(_nativeToInputRoute[i]);
        }

        for (uint j; j < _outputToNativeRoute.length; ++j) {
            outputToNativeRoute.push(_outputToNativeRoute[j]);
        }

        outputToNativeAssets = _assets[0];
        nativeToInputAssets = _assets[1];
        input.input = nativeToInputAssets[nativeToInputAssets.length - 1];
        output = outputToNativeAssets[0];
        native = nativeToInputAssets[0];
        input.isComposable = _inputIsComposable;
        balSwapOn = _balSwapOn;

        rewardsGauge = _rewardsGauge;

        funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        want = _want;
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardsGauge(rewardsGauge).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

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
            uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        if (balSwapOn) {
            IMinter minter = IMinter(IRewardsGauge(rewardsGauge).bal_pseudo_minter());
            minter.mint(rewardsGauge);
        }

        IRewardsGauge(rewardsGauge).claim_rewards();
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

    function swapRewardsToNative() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0 && balSwapOn) {
            IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(
                outputToNativeRoute,
                outputBal
            );
            BalancerActionsLib.balancerSwap(
                unirouter,
                swapKind,
                _swaps,
                outputToNativeAssets,
                funds,
                int256(outputBal)
            );
        }

        // extras
        for (uint i; i < rewardTokens.length; ++i) {
            uint bal = IERC20(rewardTokens[i]).balanceOf(address(this));
            if (bal >= rewards[rewardTokens[i]].minAmount) {
                if (rewards[rewardTokens[i]].routerType == BeefyBalancerStructs.RouterType.BALANCER) {
                    BeefyBalancerStructs.BatchSwapStruct[] memory swapInfo = new BeefyBalancerStructs.BatchSwapStruct[](
                        rewards[rewardTokens[i]].assets.length - 1
                    );
                    for (uint j; j < rewards[rewardTokens[i]].assets.length - 1; ++j) {
                        swapInfo[j] = rewards[rewardTokens[i]].swapInfo[j];
                    }
                    IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(
                        swapInfo,
                        bal
                    );
                    BalancerActionsLib.balancerSwap(
                        unirouter,
                        swapKind,
                        _swaps,
                        rewards[rewardTokens[i]].assets,
                        funds,
                        int256(bal)
                    );
                } else if (rewards[rewardTokens[i]].routerType == BeefyBalancerStructs.RouterType.UNISWAP_V3) {
                    UniV3Actions.swapV3WithDeadline(
                        rewards[rewardTokens[i]].router,
                        rewards[rewardTokens[i]].routeToNative,
                        bal
                    );
                } else if (rewards[rewardTokens[i]].routerType == BeefyBalancerStructs.RouterType.UNISWAP_V2) {
                    IUniswapRouterETH(rewards[rewardTokens[i]].router).swapExactTokensForTokens(
                        bal,
                        0,
                        rewards[rewardTokens[i]].assets,
                        address(this),
                        block.timestamp
                    );
                }
            }
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = (IERC20(native).balanceOf(address(this)) * fees.total) / DIVISOR;

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
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(
            nativeToInputRoute,
            nativeBal
        );
        BalancerActionsLib.balancerSwap(unirouter, swapKind, _swaps, nativeToInputAssets, funds, int256(nativeBal));

        if (input.input != want) {
            uint256 inputBal = IERC20(input.input).balanceOf(address(this));
            BalancerActionsLib.balancerJoin(unirouter, IBalancerPool(want).getPoolId(), input.input, inputBal);
        }
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return IRewardsGauge(rewardsGauge).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IRewardsGauge(rewardsGauge).claimable_reward(address(this), output);
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0; // multiple swap providers with no easy way to estimate native output.
    }

    function addRewardToken(
        address _token,
        address _router,
        BeefyBalancerStructs.RouterType _routerType,
        BeefyBalancerStructs.BatchSwapStruct[] memory _swapInfo,
        address[] memory _assets,
        bytes calldata _routeToNative,
        uint _minAmount
    ) external onlyOwner {
        require(_token != want, "!want");
        require(_token != native, "!native");

        if (_token == output) {
            delete outputToNativeRoute;
            delete outputToNativeAssets;

            for (uint i; i < _swapInfo.length; ++i) {
                outputToNativeRoute.push(_swapInfo[i]);
            }

            outputToNativeAssets = _assets;
            balSwapOn = true;
        } else {
            IERC20(_token).safeApprove(_router, 0);
            IERC20(_token).safeApprove(_router, type(uint).max);

            rewards[_token].routerType = _routerType;
            rewards[_token].router = _router;
            rewards[_token].assets = _assets;
            rewards[_token].routeToNative = _routeToNative;
            rewards[_token].minAmount = _minAmount;

            for (uint i; i < _swapInfo.length; ++i) {
                rewards[_token].swapInfo[i].poolId = _swapInfo[i].poolId;
                rewards[_token].swapInfo[i].assetInIndex = _swapInfo[i].assetInIndex;
                rewards[_token].swapInfo[i].assetOutIndex = _swapInfo[i].assetOutIndex;
            }

            rewardTokens.push(_token);
        }
    }

    function resetRewardTokens() external onlyManager {
        for (uint i; i < rewardTokens.length; ++i) {
            delete rewards[rewardTokens[i]];
        }

        delete rewardTokens;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        if (!input.isComposable) {
            IERC20(input.input).safeApprove(unirouter, 0);
            IERC20(input.input).safeApprove(unirouter, type(uint).max);
        }
        if (rewardTokens.length != 0) {
            for (uint i; i < rewardTokens.length; ++i) {
                IERC20(rewardTokens[i]).safeApprove(rewards[rewardTokens[i]].router, 0);
                IERC20(rewardTokens[i]).safeApprove(rewards[rewardTokens[i]].router, type(uint).max);
            }
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
        if (!input.isComposable) {
            IERC20(input.input).safeApprove(unirouter, 0);
        }
        if (rewardTokens.length != 0) {
            for (uint i; i < rewardTokens.length; ++i) {
                IERC20(rewardTokens[i]).safeApprove(rewards[rewardTokens[i]].router, 0);
            }
        }
    }
}


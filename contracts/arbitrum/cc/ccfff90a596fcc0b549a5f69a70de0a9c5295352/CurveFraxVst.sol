// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "./BaseStrategy.sol";

import {Address} from "./Address.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Math} from "./Math.sol";
import {IERC20Extended} from "./IERC20Extended.sol";

import { ICurveFi } from "./ICurveFi.sol";
import { IBalancerVault } from "./IBalancerVault.sol";
import { IBalancerPool } from "./IBalancerPool.sol";
import { IAsset } from "./IAsset.sol";
import { IUniswapV2Router02 } from "./IUniswapV2Router02.sol";
import { IStaker } from "./IStaker.sol";

interface IBaseFee {
    function isCurrentBaseFeeAcceptable() external view returns (bool);
}

contract CurveFraxVst is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    //Tokens in the LP
    IERC20 public constant vst =
        IERC20(0x64343594Ab9b56e99087BfA6F2335Db24c2d1F17);
    IERC20 public constant frax = 
        IERC20(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);

    //Reward Tokens
    IERC20 internal constant vsta =
        IERC20(0xa684cd057951541187f288294a1e1C2646aA2d24);
    IERC20 internal constant fxs = 
        IERC20(0x9d2F299715D94d8A7E6F5eaa8E654E8c74a988A7);
    
    //For swapping
    IERC20 internal constant weth =
        IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    // USDC used for swaps routing
    address internal constant usdc =
        0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    //Balancer variables for VSTA swaps
    IBalancerVault internal constant balancerVault =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    bytes32 public immutable vstaPoolId;
    bytes32 public immutable wethUsdcPoolId;
    bytes32 public immutable usdcVstPoolId;

    //Frax addresses and variables for staking
    IStaker public constant staker =
        IStaker(0x127963A74c07f72D862F2Bdc225226c3251BD117);
    //This is the time the tokens are locked for when staked
    //Inititally set to the min time, 24hours, can be updated later if desired
    uint256 public lockTime = 86400;
    //A new "kek" is created each time we stake the LP token and a whole kek must be withdrawn during any withdraws 
    //This is the max amount of Keks, we will allow the strat to have open at one time to limit withdraw loops
    uint256 public maxKeks = 5;
    //The index of the next kek to be deposited for deposit/withdraw tracking
    uint256 public nextKek;

    //Router to use for FXS -> FRAX swaps
    IUniswapV2Router02 public constant fraxRouter =
        IUniswapV2Router02(0xc2544A32872A91F4A553b404C6950e89De901fdb);
    //FXS/FRAX pool address used for harvest Trigger calculations
    address internal constant fraxPair =
        0x053B92fFA8a15b7db203ab66Bbd5866362013566;

    //Curve pool for the want LP token
    ICurveFi internal constant curvePool =
        ICurveFi(0x59bF0545FCa0E5Ad48E13DA269faCD2E8C886Ba4);

    //Timestamp of the most recent deposit to track liquid funds
    uint256 public lastDeposit;
    //Most recent amount deposited 
    uint256 public lastDepositAmount;

    //Keeper stuff
    bool public forceHarvestTriggerOnce;
    uint256 public harvestProfitMax;
    uint256 public harvestProfitMin;

    uint256 internal immutable minWant;
    uint256 public maxSingleInvest;

    constructor(address _vault) BaseStrategy(_vault) {
        require(staker.stakingToken() == want, "Wrong want for staker");

        //Set Balancer Pool Ids
        vstaPoolId = IBalancerPool(0xC61ff48f94D801c1ceFaCE0289085197B5ec44F0).getPoolId();
        wethUsdcPoolId = IBalancerPool(0x64541216bAFFFEec8ea535BB71Fbc927831d0595).getPoolId();
        usdcVstPoolId = IBalancerPool(0x5A5884FC31948D59DF2aEcCCa143dE900d49e1a3).getPoolId();

        //Set initial Keeper stuff
        harvestProfitMax = type(uint256).max;
        harvestProfitMin = 100e18;

        uint256 wantDecimals = IERC20Extended(address(want)).decimals();
        minWant = 10 ** (wantDecimals - 3);
        maxSingleInvest = 10 ** (wantDecimals + 6);

        //Approve want to staking contract
        want.safeApprove(address(staker), type(uint256).max);

        //approve both underlying tokens to curve Pool
        vst.safeApprove(address(curvePool), type(uint256).max);
        frax.safeApprove(address(curvePool), type(uint256).max);

        //Approve tokens to the routers for swaps
        fxs.safeApprove(address(fraxRouter), type(uint).max);
        vsta.safeApprove(address(balancerVault), type(uint).max);
        weth.safeApprove(address(balancerVault), type(uint).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external pure override returns (string memory) {
        return "VstFraxStaker";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function stakedBalance() public view returns (uint256) {
        return staker.lockedLiquidityOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        unchecked {
            return balanceOfWant() + stakedBalance();
        }
    }

    //Returns the total amount that cannot yet be withdrawn from the staking contract
    function stillLockedStake() public view returns (uint256 stillLocked) {
        IStaker.LockedStake[] memory stakes = staker.lockedStakesOf(address(this));
        IStaker.LockedStake memory stake;
        uint256 time = block.timestamp;
        uint256 _nextKek = nextKek;
        uint256 _maxKeks = maxKeks;
        uint256 i = _nextKek > _maxKeks ? _nextKek - _maxKeks : 0;
        for(i; i < _nextKek; i ++) {

            stake = stakes[i];

            if(stake.ending_timestamp > time) {
                unchecked {
                    stillLocked += stake.amount;
                }
            }
        }
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        //Claim, sell and reinvest rewards.
        harvester();

        //get balances of what we have
        uint256 wantBalance = balanceOfWant();
        uint256 assets = wantBalance + stakedBalance();

        //get amount given to strat by vault
        uint256 debt = vault.strategies(address(this)).totalDebt;

        uint256 needed;
        //assets - Debt is profit
        if (assets >= debt) {
            uint256 totalOwed;
            unchecked{
                _profit = assets - debt;
                totalOwed = _profit + _debtOutstanding;
            }

            if (totalOwed > wantBalance) {
                unchecked {
                    needed = totalOwed - wantBalance;
                }
            }
        } else {
            _loss = debt - assets;
            if (_debtOutstanding > wantBalance) {             
                unchecked {
                    needed = _debtOutstanding - wantBalance;
                }  
            }
        }

        //Only gets called on harvest which should be more that one Day apart so we dont need to check liquidity
        withdrawSome(needed);
        _debtPayment = Math.min(balanceOfWant() - _profit, _debtOutstanding);

        forceHarvestTriggerOnce = false;
    }

    function adjustPosition(uint256 /*_debtOutstanding*/) internal override {
        if (emergencyExit) {
            return;
        }

        //we are staking all our want up to the maxSingleInvest
        depositSome(Math.min(balanceOfWant(), maxSingleInvest));
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 _liquidWant = balanceOfWant();

        if (_liquidWant < _amountNeeded) {

            uint256 needed;
            unchecked {
                needed = _amountNeeded - _liquidWant;
            } 
   
            //Need to check that there is enough liquidity to withdraw so we dont report loss thats not true
            if(lastDeposit + lockTime > block.timestamp) {
                require(stakedBalance() - stillLockedStake() >= needed, "Need to wait till most recent deposit unlocks");
            }

            withdrawSome(needed);

            _liquidWant = balanceOfWant();
        }

        unchecked {

            if (_liquidWant >= _amountNeeded) {
                _liquidatedAmount = _amountNeeded;
            } else {
                _liquidatedAmount = _liquidWant;
                _loss = _amountNeeded - _liquidWant;
            }
        }
    }

    function depositSome(uint256 _amount) internal {
        if(_amount < minWant) return;

        //If we have already locked the max amount of keks, we need to withdraw the oldest one
        //And reinvest that along side the new funds
        if(nextKek >= maxKeks) {
            //Get the oldest kek that could have funds in it
            IStaker.LockedStake memory stake = staker.lockedStakesOf(address(this))[nextKek - maxKeks];
            //Make sure it hasnt already been withdrawn
            if(stake.amount > 0){
                //Withdraw funds and add them to the amount to deposit
                staker.withdrawLocked(stake.kek_id);
                unchecked {
                    _amount += stake.amount;
                }
            } 
        }

        staker.stakeLocked(_amount, lockTime);

        lastDeposit = block.timestamp;
        lastDepositAmount = _amount;
        nextKek ++;
    }

    function withdrawSome(uint256 _amount) internal {
        if(_amount == 0) return;

        IStaker.LockedStake[] memory stakes = staker.lockedStakesOf(address(this));

        uint256 i = nextKek > maxKeks ? nextKek - maxKeks : 0;
        uint256 needed = Math.min(_amount, stakedBalance());
        IStaker.LockedStake memory stake;
        uint256 liquidity;
        while(needed > 0 && i < nextKek) {
            stake = stakes[i];
            liquidity = stake.amount;
         
            if(liquidity > 0 && stake.ending_timestamp <= block.timestamp) {
      
                staker.withdrawLocked(stake.kek_id);

                if(liquidity < needed) {
                    unchecked {
                        needed -= liquidity;
                        i ++;
                    }
                } else {
                    break;
                }
            } else {
                unchecked{
                    i++;
                }
            }
        }
    }

    function harvester() internal {
        if(staker.lockedLiquidityOf(address(this)) > 0) {
            staker.getReward();
        }
        swapFxsToFrax();
        swapVstaToVst();
        addCurveLiquidity();
    }

    function swapFxsToFrax() internal {
        uint256 fxsBal = fxs.balanceOf(address(this));

        if(fxsBal == 0) return;

        address[] memory path = new address[](2);
        path[0] = address(fxs);
        path[1] = address(frax);

        fraxRouter.swapExactTokensForTokens(
            fxsBal, 
            0, 
            path, 
            address(this), 
            block.timestamp
        );
    }

    function swapVstaToVst() internal {
        _sellVSTAforWeth();
        _sellWethForVST();
    }

    function _sellVSTAforWeth() internal {
        uint256 _amountToSell = vsta.balanceOf(address(this));
   
        //need a min VSTA for swaps not to fail
        if(_amountToSell < 1e15) return;

        //single swap through VSTA balancer pool from vsta to weth
        //Swapping exact amount in
        IBalancerVault.SingleSwap memory singleSwap =
            IBalancerVault.SingleSwap(
                vstaPoolId,
                IBalancerVault.SwapKind.GIVEN_IN,
                IAsset(address(vsta)),
                IAsset(address(weth)),
                _amountToSell,
                abi.encode(0)
                );  

        //Create this contract as the fund manager
        //Set internal balance vars to false since it is a traditional swap
        IBalancerVault.FundManagement memory fundManagement =
            IBalancerVault.FundManagement(
                address(this),
                false,
                payable(address(this)),
                false
            );

        balancerVault.swap(
            singleSwap,
            fundManagement,
            0,
            block.timestamp
        );        
    }

     //Batch swap from WETH -> USDC -> VST through balancer
    function _sellWethForVST() internal {
        uint256 wethBalance = weth.balanceOf(address(this));
 
        if(wethBalance == 0) return;

        IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](2);

        //First trade is from Weth -> USDC for all WETH balance
        //Weth is index 0, USDC is 1, and VST is 2
        swaps[0] = IBalancerVault.BatchSwapStep(
                wethUsdcPoolId,
                0,
                1,
                wethBalance,
                abi.encode(0)
            );
        
        //Second swap from all of the USDC -> VST
        swaps[1] = IBalancerVault.BatchSwapStep(
                usdcVstPoolId,
                1,
                2,
                0,
                abi.encode(0)
            );

        //Match the token address with the desired index for this trade
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(weth));
        assets[1] = IAsset(usdc);
        assets[2] = IAsset(address(vst));

        //Create this contract as the fund manager
        //Set "use internal balance" vars to false since it is a traditional swap
        IBalancerVault.FundManagement memory fundManagement =
            IBalancerVault.FundManagement(
                address(this),
                false,
                payable(address(this)),
                false
            );
        
        //Only min we need to set is for the Weth balance going in
        int[] memory limits = new int[](3);
        limits[0] = int(wethBalance);
            
        balancerVault.batchSwap(
            IBalancerVault.SwapKind.GIVEN_IN, 
            swaps, 
            assets, 
            fundManagement, 
            limits, 
            block.timestamp
        );
    }

    function addCurveLiquidity() internal {
        uint256 fraxBal = frax.balanceOf(address(this));
        uint256 vstBal = vst.balanceOf(address(this));

        if(fraxBal == 0 && vstBal == 0) return;

        curvePool.add_liquidity(
            [vstBal, fraxBal], 
            0
        );
    }

    //Will liquidate as much as possible at the time. May not be able to liquidate all if anything has been deposited in the last day
    // Would then have to be called again after locked period has expired
    function liquidateAllPositions() internal override returns (uint256) {
        withdrawSome(type(uint256).max);
        return balanceOfWant();
    }

    //Migration should only be called if all funds are completely liquid
    //In case of problems, emergencyExit can be set to true and then harvest the strategy.
    //Or manually withdraw all liquid keks and wait until the remainder becomes liquid
    //This will allow as much of the liquid position to be withdrawn while allowing future withdraws for still locked tokens
    function prepareMigration(address _newStrategy) internal override {
        require(lastDeposit + lockTime < block.timestamp, "Latest deposit is not avialable yet for withdraw");
        withdrawSome(type(uint256).max);
    
        uint256 fxsBal = fxs.balanceOf(address(this));
        if(fxsBal > 0 ) {
            fxs.transfer(_newStrategy, fxsBal);
        }
        uint256 vstaBal = vsta.balanceOf(address(this));
        if(vstaBal > 0) {
            vsta.transfer(_newStrategy, vstaBal);
        }
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {}

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {}

    /* ========== KEEP3RS ========== */
    // use this to determine when to harvest automagically
    function harvestTrigger(uint256 /*callCostinEth*/)
        public
        view
        override
        returns (bool)
    {
        // Should not trigger if strategy is not active (no assets and no debtRatio). This means we don't need to adjust keeper job.
        if (!isActive()) {
            return false;
        }

        // harvest if we have a profit to claim at our upper limit without considering gas price
        uint256 claimableProfit = getClaimableProfit();
        if (claimableProfit > harvestProfitMax) {
            return true;
        }

        // check if the base fee gas price is higher than we allow. if it is, block harvests.
        if (!isBaseFeeAcceptable()) {
            return false;
        }

        // trigger if we want to manually harvest, but only if our gas price is acceptable
        if (forceHarvestTriggerOnce) {
            return true;
        }

        // harvest if we have a sufficient profit to claim, but only if our gas price is acceptable
        if (claimableProfit > harvestProfitMin) {
            return true;
        }

        // Should trigger if hasn't been called in a while
        if (block.timestamp - vault.strategies(address(this)).lastReport >= maxReportDelay) {
            return true;
        }

        // otherwise, we don't harvest
        return false;
    }

    //Returns the estimated claimable profit in want. 
    function getClaimableProfit() public view returns (uint256 _claimableProfit) {
        uint256 assets = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        //Only use the Frax rewards
        (uint256 fxsEarned, ) = staker.earned(address(this));
        fxsEarned += fxs.balanceOf(address(this));

        uint256 estimatedRewards;
        if(fxsEarned > 0 ) {
            
            uint256 fxsToFrax = fraxRouter.getAmountOut(
                fxsEarned, 
                fxs.balanceOf(fraxPair), 
                frax.balanceOf(fraxPair)
            );

            estimatedRewards = curvePool.calc_token_amount(
                [0, fxsToFrax], 
                true
            );
        }

        assets += estimatedRewards;
        _claimableProfit = assets > debt ? assets - debt : 0;
    }

    //Function available to Governance to manually withdraw a specific kek
    //Available if the counter or loops fail
    //Pass the index of the kek to withdraw as the param
    function manualWithdraw(uint256 index) external onlyEmergencyAuthorized {
        staker.withdrawLocked(
            staker.lockedStakesOf(address(this))[index].kek_id
        );
    }

    //This can be used to update how long the tokens are locked when staked
    //Care should be taken when increasing the time to only update directly before a harvest
    //Otherwise the timestamp checks when withdrawing could be inaccurate
    function setLockTime(uint256 _lockTime) external onlyVaultManagers {
        require(_lockTime >= staker.lock_time_min(), "Too low");
        lockTime = _lockTime;
    }

    //Function to change the allowed amount of max keks
    //Will withdraw funds if lowering the max. Should harvest after maxKeks is lowered
    function setMaxKeks(uint256 _maxKeks) external onlyVaultManagers {
        //If we are lowering the max we need to withdraw the diff if we are already over the new max
        if(_maxKeks < maxKeks && nextKek > _maxKeks) {
            uint256 toWithdraw = maxKeks - _maxKeks;
            IStaker.LockedStake[] memory stakes = staker.lockedStakesOf(address(this));
            IStaker.LockedStake memory stake;
            for(uint256 i; i < toWithdraw; i ++){
                stake = stakes[nextKek - maxKeks + i];

                //Need to make sure the kek can be withdrawn and is > 0
                if(stake.amount > 0) {
                    require(stake.ending_timestamp < block.timestamp, "Not liquid");
                    staker.withdrawLocked(stake.kek_id);
                }
            }
        }
        maxKeks = _maxKeks;
    }

    function setMaxSingleInvestment(uint256 _maxSingleInvest) external onlyVaultManagers {
        maxSingleInvest = _maxSingleInvest;
    }

    function setKeeperStuff(
        uint256 _harvestProfitMax, 
        uint256 _harvestProfitMin
    ) external onlyVaultManagers {
        harvestProfitMax = _harvestProfitMax;
        harvestProfitMin = _harvestProfitMin;
    }

    // This allows us to manually harvest with our keeper as needed
    function setForceHarvestTriggerOnce(bool _forceHarvestTriggerOnce)
        external
        onlyVaultManagers
    {
        forceHarvestTriggerOnce = _forceHarvestTriggerOnce; 
    }

    // check if the current baseFee is below our external target
    function isBaseFeeAcceptable() internal view returns (bool) {
        return
            IBaseFee(0xdF43263DFec19117f2Fe79d1D9842a10c7495CcD)
                .isCurrentBaseFeeAcceptable();
    }
}

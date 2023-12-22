// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.4;

import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {SafeMath} from "./SafeMath.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Beefy} from "./Beefy.sol";
import {ShareMathBeefy} from "./ShareMathBeefy.sol";
import {ExoticOracleInterface} from "./ExoticOracleInterface.sol";
import {PolysynthKikoVaultStorage} from "./PolysynthKikoVaultStorage.sol";
import {BeefyVault} from "./BeefyVault.sol";
import {IGlpRouter} from "./IGlpRouter.sol";
import {IBeefy} from "./IBeefy.sol";
import "./console.sol";

contract PolysynthBeefyVaultGLP is 
    BeefyVault,
    PolysynthKikoVaultStorage
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using ShareMathBeefy for Beefy.DepositReceipt;

    IGlpRouter  glpRouter;
    address glpManager;
    address usdcToken;
    // Burnt shares for the current round

    constructor(
        address _vault        
    ) BeefyVault(_vault){}

    function initialize(
        address _owner,
        address _keeper,
        address _feeRecipent,        
        string memory _tokenName,
        string memory _tokenSymbol,
        Beefy.VaultParams calldata _vaultParams,
        IGlpRouter _glpRouter,
        address _token
    ) external initializer {
        glpRouter = _glpRouter;
        glpManager = glpRouter.glpManager();
        usdcToken = _token;
        baseInitialize(_owner, _keeper, _feeRecipent, _tokenName, _tokenSymbol, _vaultParams);
    }

    modifier onlyObserver() {
        require(msg.sender == observer, "!observer");
        _;
    }

    function setGlpRewardRouter(address _glpRouter) external onlyOwner {
        require(_glpRouter != address(0), "valid glp address");
        glpRouter = IGlpRouter(_glpRouter);
        glpManager = glpRouter.glpManager();
    }

    function setAuctionTime(uint256 _auctionTime) external onlyOwner {
        require(_auctionTime != 0, "!_auctionTime");
        auctionTime = _auctionTime;
    }

    function setObserver(address _newObserver) external onlyOwner {
        require(_newObserver != address(0), "!_newObserver");
        observer = _newObserver;
    }

    function setVaultPeriod(uint256 _vaultPeriod) external onlyOwner {
        require(_vaultPeriod > 0, "!invalid");
        vaultParams.vaultPeriod = _vaultPeriod;
    }

    // /**
    //  * @notice Initiates a withdrawal that can be processed once the round completes
    //  * @param numShares is the number of shares to withdraw
    //  */
    // function initiateWithdraw(uint256 numShares) external nonReentrant {
    //     _initiateWithdraw(numShares);
    //     currentQueuedWithdrawShares = currentQueuedWithdrawShares.add(
    //         numShares
    //     );
    // }

    // /**
    //  * @notice Completes a scheduled withdrawal from a past round. Uses finalized pps for the round
    //  */
    // function completeWithdraw() external nonReentrant {
    //     uint256 withdrawAmount = _completeWithdraw();
    //     lastQueuedWithdrawAmount = uint128(
    //         uint256(lastQueuedWithdrawAmount).sub(withdrawAmount)
    //     );
    // }

     /**
     * @notice withdraw shares
     * @param numShares is the number of shares to withdraw
     */
    function withdraw(uint256 numShares) external nonReentrant {
        vaultState.burntAmount += uint128(_withdraw(numShares));
        vaultState.burntShares += uint128(numShares);
    }

    function close() external nonReentrant onlyKeeper {
        // console.log("CLOSING ROUND %s PPS %s ", vaultState.round,  pricePerShare());
        // 1, Check if settlement is done by MM
        // 2. Calculate PPS
        require(
            optionState.isSettled || vaultState.round < 3,
            "Round closed"
        );        
        
        Beefy.VaultResp memory vr;

       // Old withdraw
       // uint256 currQueuedWithdrawShares = currentQueuedWithdrawShares;
       (vr.performanceFee, vr.managementFee,  ) = _closeRound();
        // lastQueuedWithdrawAmount = queuedWithdrawAmount;

        vaultState.prevRoundAmount = vaultState.unlockedAmount;
        vaultState.lockedAmount = vaultState.lockedAmount + vaultState.prevRoundAmount;
        vaultState.unlockedAmount = 0;
    
        IBeefy bv = IBeefy(BEEFY_VAULT);
        vr.bps = bv.getPricePerFullShare();
        vr.currMoobalance = bv.balanceOf(address(this));
        vr.currentRound = vaultState.round;
        vr.totalFee = vr.managementFee.add(vr.performanceFee);
        
        console.log("Currbalance %s unlockedAmount %s settledAmount %s", vr.currMoobalance, vaultState.prevRoundAmount, optionState.settledAmount);

        if(vr.currMoobalance.add(vr.totalFee).add(optionState.unSettledYield) >= uint256(vaultState.prevRoundAmount).add(uint256(optionState.settledAmount))){
            // deployed balance must not have settle amount | Add fees to retrieve previous vaultbalance
            vr.deployedbalance = vr.currMoobalance.add(vr.totalFee).add(optionState.unSettledYield).sub(vaultState.prevRoundAmount).sub(optionState.settledAmount);
            vr.lastRoundbps = optionState.beefyPPS;
            
            //Set currrent round bps
            optionState.beefyPPS = vr.bps;
            // optionState.lockedAmount = currbalance;
            uint256 accruedYield = vr.bps - vr.lastRoundbps;
            vr.mooYieldShares = (accruedYield * vr.deployedbalance)/vr.bps;
           
            console.log("BPS %s lastRoundbps %s mooYieldShares %s", vr.bps, vr.lastRoundbps, vr.mooYieldShares);
            console.log("Deployedbalance %s lockedAmount %s settledAmount %s", vr.deployedbalance, vaultState.prevRoundAmount, optionState.settledAmount);

            if(vr.currentRound > 2  
                && vr.mooYieldShares > 0){   
                
                vr.glpYieldShares = (vr.mooYieldShares * vr.bps) / TOKEN_DECIMALS;
                //get glp token from beefy vault by selling mooToken
                bv.withdraw(vr.mooYieldShares);

                console.log("MooYieldShares %s GlpYieldShares %s currbalance %s", vr.mooYieldShares, vr.glpYieldShares, vr.currMoobalance);

                //Get USDC by selling GLP Token
                uint256 usdcBalanceBefore = IERC20(usdcToken).balanceOf(address(this));
                _sellGlpToken(vr.glpYieldShares);
                vr.currMoobalance = bv.balanceOf(address(this));
                uint256 usdcBalanceAfter = IERC20(usdcToken).balanceOf(address(this));
                optionState.borrowAmount = (usdcBalanceAfter - usdcBalanceBefore);

                console.log("USDC %s currbalance %s", optionState.borrowAmount, vr.currMoobalance);

            }
        }else{
            optionState.borrowAmount = 0;
        }


        vaultState.burntShares  = 0;
        vaultState.burntAmount = 0;
        optionState.unSettledYield = 0;
        optionState.isSettled = false;
        optionState.isBorrowed = false;
        optionState.expiry = getNextExpiry();

        emit InterestRedeem(
            optionState.borrowAmount,
            vr.mooYieldShares,
            vr.glpYieldShares,
            vr.deployedbalance,
            vr.currentRound
        );
    }

    function borrow() external nonReentrant {
        if(optionState.borrowAmount > 0){
            require(!optionState.isBorrowed,"already borrowed");
            require(msg.sender == borrower, "unauthorised");  
            transferAssetByAddress(usdcToken, payable(borrower), optionState.borrowAmount);
        }
        
        // Event for borrow amount
        emit Borrow(borrower, optionState.borrowAmount, 0);
        optionState.isBorrowed = true;
    }


    function settle(uint256 _amount) external nonReentrant {
        require(block.timestamp>=optionState.expiry, "early settle");
        require(!optionState.isSettled,"already settled");
        require(optionState.isBorrowed, "not yet borrowed");
        require(msg.sender == borrower, "unauthorised");
        
        uint256 prevBalance;
        uint256 afterBalance;

        if(_amount == 0 ){
            optionState.isSettled = true;
        }else{
            IERC20(usdcToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );

            prevBalance = IERC20(vaultParams.asset).balanceOf(address(this));
            IERC20(usdcToken).approve(glpManager, _amount);
            _buyGlpToken(_amount, 0);
            afterBalance = IERC20(vaultParams.asset).balanceOf(address(this));
        }

        optionState.settledAssetAmount = afterBalance.sub(prevBalance);
        optionState.couponAmount = _amount;
        console.log("SETTLE USDC %s GLP  %s", _amount, optionState.settledAssetAmount);

    }

    function settleGlp() external onlyKeeper nonReentrant {
        uint256 prevBalance;
        uint256 afterBalance;

        if(optionState.settledAssetAmount > 0){
            IBeefy bv = IBeefy(BEEFY_VAULT);
            IERC20(vaultParams.asset).approve(BEEFY_VAULT, optionState.settledAssetAmount);
            prevBalance = IERC20(BEEFY_VAULT).balanceOf(address(this));
            bv.deposit(optionState.settledAssetAmount);
            afterBalance = IERC20(BEEFY_VAULT).balanceOf(address(this));
        }

        optionState.settledAmount = afterBalance.sub(prevBalance);
        optionState.settledAssetAmount = 0;
        optionState.isSettled = true;

        // Event for settle
        emit Settle(borrower, optionState.couponAmount, 
                optionState.settledAssetAmount, optionState.settledAmount);
    }


    function accountBalance(address _account) external view 
            returns(uint256 balance, uint256 balanceA, uint256 balanceB, uint256 sharesBalance) {
        return getAccountBalance(_account);
    }
    
    
    function _closeRound() internal returns (uint256 performanceFeeInAsset,uint256 managementFeeInAsset, uint256 queuedWithdrawAmount){
        address recipient = feeRecipient;
        uint256 mintShares;
        uint256 totalVaultFee;
        
        {
            uint256 newPricePerShare;

            uint256 currentBalance = IERC20(BEEFY_VAULT).balanceOf(address(this));
            uint256 pendingAmount = vaultState.prevRoundAmount + vaultState.unlockedAmount;

            uint256 currentShareSupply = totalSupply();
            uint256 currentRound = vaultState.round;
            
            uint256 balanceForVaultFees = currentBalance.sub(pendingAmount);

            {
                (performanceFeeInAsset, managementFeeInAsset, totalVaultFee) = getVaultFees(
                    balanceForVaultFees,
                    performanceFee,
                    managementFee                    
                );
            }

            uint256 tempBalance = currentBalance.sub(totalVaultFee);

            {
                newPricePerShare = ShareMathBeefy.pricePerShare(
                    currentShareSupply.add(vaultState.burntShares), //shares withdrawn
                    tempBalance.add(vaultState.burntAmount), // burnt shares withdrawn
                    pendingAmount,
                    vaultParams.decimals
                );

                _settleUnAccountedYield(newPricePerShare);

                // After closing the short, if the options expire in-the-money
                // vault pricePerShare would go down because vault's asset balance decreased.
                // This ensures that the newly-minted shares do not take on the loss.
                mintShares = ShareMathBeefy.assetToShares(
                    vaultState.prevRoundAmount,
                    newPricePerShare,
                    vaultParams.decimals
                );
            }

            // Finalize the pricePerShare at the end of the round
            roundPricePerShare[currentRound] = newPricePerShare;

            emit CollectVaultFees(
                performanceFeeInAsset,
                totalVaultFee,
                currentRound,
                recipient
            );

            // vaultState.totalPending = 0;
            vaultState.round = uint16(currentRound + 1);
            console.log("CLOSEEEE mintShares %s newPricePerShare %s ", mintShares, newPricePerShare);
        }

        _mint(address(this), mintShares);

        if (totalVaultFee > 0) {
            transferAssetByAddress(BEEFY_VAULT, payable(feeRecipient), totalVaultFee);
        }     

        return (performanceFeeInAsset,managementFeeInAsset, 0);
    }

    function _settleUnAccountedYield(uint256 newPricePerShare) internal {
        uint256 withdrawAmountAtNewPPS = ShareMathBeefy.sharesToAsset(
            vaultState.burntShares,
            newPricePerShare,
            vaultParams.decimals
        );
        
        optionState.unSettledYield = withdrawAmountAtNewPPS > vaultState.burntAmount ? withdrawAmountAtNewPPS.sub(vaultState.burntAmount) : 0;
        console.log("CLOSEE withdrawAmountAtNewPPS %s withdrawAmount %s unAccountedyield", withdrawAmountAtNewPPS,vaultState.burntAmount, optionState.unSettledYield);
        if(optionState.unSettledYield > 0){
            transferAssetByAddress(BEEFY_VAULT, payable(feeRecipient), optionState.unSettledYield);
        }
    }


    function _buyGlpToken(uint256 _usdcAmount, uint256 _minGlpAmount) internal {
        glpRouter.mintAndStakeGlp(usdcToken, _usdcAmount, 0, _minGlpAmount);
    }

    function _sellGlpToken(uint256 _glpAmount) internal {
        glpRouter.unstakeAndRedeemGlp(usdcToken, _glpAmount, 0, address(this));
    }

}


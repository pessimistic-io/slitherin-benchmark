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
    uint256 public currentBurntShares;

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
        _withdraw(numShares);
        currentBurntShares = currentBurntShares.add(
            numShares
        );
    }

    function close() external nonReentrant onlyKeeper {
        // console.log("CLOSING ROUND %s PPS %s ", vaultState.round,  pricePerShare());
        // 1, Check if settlement is done by MM
        // 2. Calculate PPS
        require(
            optionState.isSettled || vaultState.round < 3,
            "Round closed"
        );        
        
       // Old withdraw
       // uint256 currQueuedWithdrawShares = currentQueuedWithdrawShares;
       (uint256 totalFees, uint256 queuedWithdrawAmount) = _closeRound();
        lastQueuedWithdrawAmount = queuedWithdrawAmount;

        //Settle beefy transfers
        IBeefy bv = IBeefy(BEEFY_VAULT);
        uint256 bps = bv.getPricePerFullShare();
        uint256 currbalance = bv.balanceOf(address(this));

        console.log("Currbalance %s unlockedAmount %s settledAmount %s", currbalance, vaultState.unlockedAmount, optionState.settledAmount);

        // deployed balance must not have settle amount | Add fees to retrieve previous vaultbalance
        uint256 deployedbalance = currbalance.add(totalFees).sub(vaultState.unlockedAmount).sub(optionState.settledAmount);
        uint256 lastRoundbps = optionState.beefyPPS;
        
        //Set currrent round bps
        optionState.beefyPPS = bps;
        // optionState.lockedAmount = currbalance;
        uint256 accruedYield = bps - lastRoundbps;
        uint256 mooYieldShares = (accruedYield * deployedbalance)/bps;
        uint256 currentRound = vaultState.round;
        console.log("BPS %s lastRoundbps %s mooYieldShares %s", bps, lastRoundbps, mooYieldShares);
        console.log("Deployedbalance %s lockedAmount %s settledAmount %s", deployedbalance, vaultState.prevRoundAmount, optionState.settledAmount);

        if(currentRound > 2  
            && mooYieldShares > 0){   
            uint256 glpYieldShares = (mooYieldShares *bps) / TOKEN_DECIMALS;
            console.log("MooYieldShares %s GlpYieldShares %s currbalance %s", mooYieldShares, glpYieldShares, currbalance);

            //get glp token from beefy vault by selling mooToken
            bv.withdraw(mooYieldShares);

            uint256 usdcBalanceBefore = IERC20(usdcToken).balanceOf(address(this));

            //Get USDC by selling GLP Token
            _sellGlpToken(glpYieldShares);

            currbalance = bv.balanceOf(address(this));
            uint256 usdcBalanceAfter = IERC20(usdcToken).balanceOf(address(this));

            console.log("USDC %s currbalance %s",(usdcBalanceAfter - usdcBalanceBefore), currbalance);
            optionState.borrowAmount = (usdcBalanceAfter - usdcBalanceBefore);
            emit InterestRedeem(
                optionState.borrowAmount,
                mooYieldShares,
                glpYieldShares,
                deployedbalance,
                currentRound
            );
        }
        
        // OLD WITHDRAW
        // uint256 newQueuedWithdrawShares =
        //     uint256(vaultState.queuedWithdrawShares).add(
        //         currQueuedWithdrawShares
        //     );
        // ShareMathBeefy.assertUint128(newQueuedWithdrawShares);
        // vaultState.queuedWithdrawShares = uint128(newQueuedWithdrawShares);
        
        currentBurntShares = 0;
        vaultState.prevRoundAmount = vaultState.unlockedAmount;
        vaultState.unlockedAmount = 0;
        vaultState.lockedAmount = vaultState.lockedAmount + vaultState.prevRoundAmount;
        
        optionState.isSettled = false;
        optionState.isBorrowed = false;
        optionState.expiry = getNextMonday(block.timestamp);
    }

    function borrow() external nonReentrant {
        require(!optionState.isBorrowed,"already borrowed");
        require(msg.sender == borrower, "unauthorised");  
        require(optionState.borrowAmount > 0, "Borrowed Amount is zero"); 

        transferAssetByAddress(usdcToken, payable(borrower), optionState.borrowAmount);

        // Event for borrow amount
        emit Borrow(borrower, optionState.borrowAmount, 0);
        optionState.isBorrowed = true;
     }


    function settle(uint256 _amount) external nonReentrant {
        require(!optionState.isSettled,"already settled");
        require(optionState.isBorrowed,"not yet borrowed");
        require(msg.sender == borrower, "unauthorised");
        // require(_amount > 0, "Settle amount must be greater than zero.");

        //Transfer USDC token
        IERC20(usdcToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 prevBalance = IERC20(vaultParams.asset).balanceOf(address(this));
        IERC20(usdcToken).approve(glpManager, _amount);
        _buyGlpToken(_amount, 0);
        uint256 afterBalance = IERC20(vaultParams.asset).balanceOf(address(this));
        optionState.settledAssetAmount = afterBalance.sub(prevBalance);
        console.log("SETTLE USDC %s GLP  %s", _amount, optionState.settledAssetAmount);
        require(optionState.settledAssetAmount > 0 ,"Asset balance low");
        optionState.couponAmount = _amount;
    }

    function settleGlp() external onlyKeeper nonReentrant {
        require(optionState.settledAssetAmount > 0, "Settle amount must be greater than zero.");
        IBeefy bv = IBeefy(BEEFY_VAULT);
        IERC20(vaultParams.asset).approve(BEEFY_VAULT, optionState.settledAssetAmount);
        uint256 prevBalance = IERC20(BEEFY_VAULT).balanceOf(address(this));
        bv.deposit(optionState.settledAssetAmount);
        uint256 afterBalance = IERC20(BEEFY_VAULT).balanceOf(address(this));
        optionState.settledAmount = afterBalance.sub(prevBalance);
        optionState.settledAssetAmount = 0;
        optionState.isSettled = true;

        // Event for settle
        emit Settle(borrower, optionState.couponAmount, optionState.settledAssetAmount, optionState.settledAmount);
    }
    
    
    function _closeRound() internal returns (uint256 totalVaultFee, uint256 queuedWithdrawAmount){
        address recipient = feeRecipient;
        uint256 mintShares;
        uint256 performanceFeeInAsset;
        {
            uint256 newPricePerShare;

            uint256 currentBalance = IERC20(BEEFY_VAULT).balanceOf(address(this));
            uint256 pendingAmount = vaultState.prevRoundAmount + vaultState.unlockedAmount;
            uint256 currentShareSupply = totalSupply();
            uint256 currentRound = vaultState.round;
            uint256 withdrawAmount;

            uint256 balanceForVaultFees =
                currentBalance.sub(pendingAmount);

            {
                (performanceFeeInAsset, , totalVaultFee) = getVaultFees(
                    balanceForVaultFees,
                    performanceFee,
                    managementFee                    
                );
            }

            currentBalance = currentBalance.sub(totalVaultFee);
            {   
                withdrawAmount = currentBurntShares == 0 ? 0 : ShareMathBeefy.sharesToAsset(
                    currentBurntShares,
                    roundPricePerShare[currentRound-1],
                    vaultParams.decimals
                );


                newPricePerShare = ShareMathBeefy.pricePerShare(
                    currentShareSupply.add(currentBurntShares), //shares withdrawn
                    currentBalance.add(withdrawAmount), // burnt shares withdrawn
                    pendingAmount,
                    vaultParams.decimals
                );

                _settleUnAccountedYield(withdrawAmount, newPricePerShare);

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
            transferAssetByAddress(BEEFY_VAULT, payable(recipient), totalVaultFee);
        }     

        return (totalVaultFee, 0);
    }

    function _settleUnAccountedYield(uint256 withdrawAmount, uint256 newPricePerShare) internal {
        uint256 withdrawAmountAtNewPPS = ShareMathBeefy.sharesToAsset(
            currentBurntShares,
            newPricePerShare,
            vaultParams.decimals
        );
        
        uint256 unAccountedyield = withdrawAmountAtNewPPS > withdrawAmount ? withdrawAmountAtNewPPS.sub(withdrawAmount) : 0;

        if(unAccountedyield > 0){
            IERC20(BEEFY_VAULT).transfer(feeRecipient, unAccountedyield);
        }
    }


    function _buyGlpToken(uint256 _usdcAmount, uint256 _minGlpAmount) internal {
        glpRouter.mintAndStakeGlp(usdcToken, _usdcAmount, 0, _minGlpAmount);
    }

    function _sellGlpToken(uint256 _glpAmount) internal {
        glpRouter.unstakeAndRedeemGlp(usdcToken, _glpAmount, 0, address(this));
    }
}

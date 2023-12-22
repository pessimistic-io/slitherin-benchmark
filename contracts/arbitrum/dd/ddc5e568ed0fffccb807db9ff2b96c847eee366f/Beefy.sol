// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.4;

library Beefy {
    /************************************************
     *  IMMUTABLES & CONSTANTS
     ***********************************************/

    // Fees are 6-decimal places. For example: 20 * 10**6 = 20%
    uint256 internal constant FEE_MULTIPLIER = 10**6;

    uint256 internal constant RATIO_MULTIPLIER = 10**4;

    // Placeholder uint value to prevent cold writes
    uint256 internal constant PLACEHOLDER_UINT = 1;

    struct VaultParams {        
        // Token decimals for vault shares
        uint8 decimals;
        // Asset used in Kiko Vault
        address asset;
        // Beefy vault address
        address beefyVault;
        // Minimum supply of the vault shares issued, for ETH it's 10**10
        uint56 minimumSupply;
        // Vault cap
        uint104 cap;        
        // Vault lifecycle duration in seconds
        uint256 vaultPeriod;
    }
    
    struct VaultState {
        // 32 byte slot 1
        //  Current round number. `round` represents the number of `period`s elapsed.
        uint16 round;
        // Amount that is currently locked for selling options
        uint104 lockedAmount;
        // Amount that is currently unlocked for yield farming
        uint104 unlockedAmount;
        // Amount that is currently unlocked for previous yield farming
        uint104  prevRoundAmount;
        // Amount that was locked for selling options in the previous round
        // used for calculating performance fee deduction
        uint104 lastLockedAmount;
        // 32 byte slot 2
        // Stores the total tally of how much of `asset` there is
        // to be used to mint rKIKO tokens
        uint128 totalPending;

        uint128 burntShares;

        uint128 burntAmount;
    }

    struct OptionState {  
        // Amount that is currently locked in beefy vault for selling options   
        uint256 lockedAmount;   
        // USDC Amount that is currently available for borrowing from vault
        uint256 borrowAmount;   
        // USDC Amount that is currently settled
        uint256 couponAmount;   
        // Asset Amount that is currently settled
        uint256 settledAssetAmount;
        // Total amount settled in beefy token
        uint256 settledAmount;
        // un settled yiedl due to pre mature withdraw
        uint256 unSettledYield;
        // Last recorded PPS of the beefy vault
        uint256 beefyPPS;        
        // Expiry of the current round
        uint256 expiry;     
        // settled of the current round
        bool isSettled;      
        // borrowed of the current round
        bool isBorrowed;
        // Timestamp at the time of last observation
        uint256 lastObservation;
    }

    struct DepositReceipt {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Deposit amount, max 20,282,409,603,651 or 20 trillion ETH deposit
        uint104 amount;
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 roundB;
        // Deposit amount, max 20,282,409,603,651 or 20 trillion ETH deposit
        uint104 amountB;
        // Unredeemed shares balance
        uint128 unredeemedShares;
    }

    struct Withdrawal {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Number of shares withdrawn
        uint128 shares;
    } 

    struct VaultResp {
        uint256 pps;
        uint256 bps;
        uint16 currentRound;
        uint256 currMoobalance;
        uint256 lastRoundbps;
        uint256 nexRoundPPS;
        uint256 deployedbalance;
        uint256 accruedYield;
        uint256 mooYieldShares;
        uint256 glpYieldShares;
        uint256 totalFee;
        uint256 managementFee;
        uint256 performanceFee;  
    }
       
}


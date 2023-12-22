// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

library VaultDataTypes {
    
    enum LockupPeriod {
        THREE_MONTHS,
        SIX_MONTHS,
        TWELVE_MONTHS
    }

    struct VaultData {
        address SVS;
        address stable;
        uint256 initShareValue;
        uint256 currentTranche;
        address[] VITs;
        uint256[] VITAmounts;
        uint256[] lockupTimes;
        uint256 stableDeposited;
        uint256 stableHardcap;
        bool batchMintEnabled;
        bool batchRedeemEnabled;
        VaultFee fee;
    }

    struct VaultFee {
        uint256 depositFee; // 1 represents 0.01%
        uint256 redemptionFee;
        //uint256 rewardFee; //not used in v1.0
    }

    struct VaultShare {
        uint256 tranche;
        address[] tokens;
        uint256[] tokenAmounts;
        uint256 lastRebalanced;
    }

    struct MintParams {
        uint256 numShares;
        uint256 stableAmount;
        uint256[] amountPerSwap;
        VaultDataTypes.LockupPeriod lockup;
        address stable;
        address[] VITs;
        uint256[] VITAmounts;
        uint256 currentTranche;
        address swapRouter;
        address svs;
        uint256 depositFee;
        address vaultAddress;
    }   

    struct PendingMint {
        uint256 amountUSDC;
        VaultDataTypes.LockupPeriod lockup;
    }

    struct UserMintRequest {
        uint256 amountUSDC;
        uint256 tranche;
    }
}

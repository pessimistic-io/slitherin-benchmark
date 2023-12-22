// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./MasterStorage.sol";

interface IHelper {
    // !!!!
    // @dev
    // an artificial uint256 param for metadata should be added
    // after packing the payload
    // metadata can be generated via call to ecc.preRegMsg()

    struct MDeposit {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.MASTER_DEPOSIT
        address user;
        address pToken;
        uint256 externalExchangeRate;
        uint256 depositAmount;
    }

    struct MWithdraw {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.MASTER_WITHDRAW
        address pToken;
        address user;
        uint256 withdrawAmount;
        uint256 targetChainId;
    }

    struct FBWithdraw {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.FB_WITHDRAW
        address pToken;
        address user;
        uint256 withdrawAmount;
        uint256 externalExchangeRate;
    }

    struct MRepay {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.MASTER_REPAY
        address borrower;
        uint256 amountRepaid;
        address loanAsset;
    }

    struct MBorrow {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.MASTER_BORROW
        address user;
        uint256 borrowAmount;
        address loanAsset;
        uint256 targetChainId;
    }

    struct FBBorrow {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.FB_BORROW
        address user;
        uint256 borrowAmount;
        address loanAsset;
    }

    struct SLiquidateBorrow {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.SATELLITE_LIQUIDATE_BORROW
        address borrower;
        address liquidator;
        uint256 seizeTokens;
        address pToken;
        uint256 externalExchangeRate;
    }

    struct SRefundLiquidator {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.SATELLITE_REFUND_LIQUIDATOR
        address liquidator;
        uint256 refundAmount;
        address loanAsset;
    }

    struct MLiquidateBorrow {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.MASTER_LIQUIDATE_BORROW
        address liquidator;
        address borrower;
        address seizeToken;
        uint256 seizeTokenChainId;
        address loanAsset;
        uint256 repayAmount;
    }

    struct LoanAssetBridge {
        uint256 metadata; // LEAVE ZERO
        bytes4 selector; // = Selector.LOAN_ASSET_BRIDGE
        address minter;
        bytes32 loanAssetNameHash;
        uint256 amount;
    }
}


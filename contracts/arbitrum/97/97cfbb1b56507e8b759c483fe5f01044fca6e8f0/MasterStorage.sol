// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./Selector.sol";
import "./AdminControl.sol";
import "./IPrimeOracle.sol";
import "./IMiddleLayer.sol";
import "./IIRMRouter.sol";
import "./ICRMRouter.sol";

abstract contract MasterStorage is Selector, AdminControl {

    /// @notice The address of MasterInternals
    address public masterInternals;

    // slither-disable-next-line unused-state
    IMiddleLayer internal middleLayer;

    // slither-disable-next-line unused-state
    IIRMRouter public interestRateModel;
    ICRMRouter public collateralRatioModel;
    IPrimeOracle public oracle;

    uint8 public immutable FACTOR_DECIMALS = 8;
    uint8 public immutable FEE_PRECISION = 18;
    uint8 public immutable EXCHANGE_RATE_DECIMALS = 18;
    uint256 public totalUsdCollateralBalance;

    struct MarketIndex {
        uint256 chainId;  /// @notice The chainId on which the market exists
        address pToken; /// @notice The asset for which this market exists, e.g. e.g. USP, pBTC, pETH.
    }

    /// @notice Represents one of the collateral available on a given satellite chain. Key: <chainId, token>
    struct Market {
        uint256 externalExchangeRate;
        uint256 lastExchangeRateTimestamp;
        uint256 totalCollateralValue;
        uint256 totalSupply;
        uint256 liquidityIncentive;
        uint256 protocolSeizeShare;
        address underlying;
        uint8 decimals;
        bool isListed;
        bool isRebase;
    }

    struct MarketMetadata {
        uint256 chainId;
        address asset;
    }

    /// @notice Array of all collateral market indices, lazily in descending order of totalCollateralValue.
    MarketIndex[] public collateralValueIndex;

    /// @notice Mapping of account addresses to pToken collateral balances
    mapping(uint256 /* chainId */ => mapping(address /* user */ => mapping(address /* token */ => uint256 /* collateralBalance */))) public pTokenCollateralBalances;

    /// @notice Mapping of tokens -> max acceptable percentage risk by the protocol; precision of 8; 1e8 = 100%
    /// @notice Set to 1 if you want to disable this asset
    mapping(uint256 /* chainId */ => mapping(address /* token */ => uint256)) public maxCollateralPercentages;

    /// @notice Mapping of all depositors currently using this collateral market.
    mapping(address /* user */ => mapping(uint256 /* chainId */ => mapping(address /* token */ => bool /* isMember */))) public accountMembership;

    /// @notice Official mapping of tokens -> Market metadata.
    mapping(uint256 /* chainId */ => mapping(address /* token */ => Market)) public markets;

    /// @notice All collateral markets in use by a particular user.
    mapping(address /* user */ => MarketIndex[]) public accountCollateralMarkets;

    /// @notice Container for borrow balance information
    struct BorrowSnapshot {
        uint256 principal; /// @notice Total balance (with accrued interest), after applying the most recent balance-changing action
        uint256 interestIndex; /// @notice Global borrowIndex as of the most recent balance-changing action
    }

    /// @notice Represents one of the loan markets available by all satellite loan agents. Key: <chainId, loanMarketAsset>
    struct LoanMarket {
        uint256 accrualBlockNumber; /// @notice Block number that interest was last accrued at
        uint256 totalReserves; /// @notice Total amount of protocol owned reserves of the underlying held in this market.
        uint256 totalBorrows; /// @notice Total amount of outstanding borrows of the underlying in this market.
		uint256 borrowIndex; /// @notice Accumulator of the total earned interest rate since the opening of the market.
        uint256 underlyingChainId; /// @notice The chainId on which the underlying asset exists.
        address underlying; /// @notice The underlying asset for which this loan market exists, e.g. USP, BTC, ETH.
        uint8 decimals; /// @notice The decimals of the underlying asset, e.g. 18.
        bool isListed;  /// @notice Whether or not this market is listed.

        // Ptoken specific assets
        uint256 totalSupplied;
        uint256 adminFee;
    }

    /// @notice Mapping of account addresses to outstanding borrow balance.
    mapping(address /* borrower */ => mapping(address /* loanAsset */ => mapping(uint256 /* chainId */ => BorrowSnapshot))) public accountLoanMarketBorrows;

    mapping(address /* borrower */ => mapping(address /* loanAsset */ => mapping(uint256 /* chainId */ => uint256))) public repayCredit;

    /// @notice Mapping of all borrowers currently using this loan market.
    mapping(address /* borrower */ => mapping(address /* loanAsset */ => mapping(uint256 /* chainId */ => bool /* isMember */))) public isLoanMarketMember;

    /// @notice All currently supported loan market assets, e.g. USP, pBTC, pETH.
    mapping(address /* loanAsset */ => mapping(uint256 /* chainId */ => LoanMarket)) public loanMarkets;

    struct LoanMarketMetadata {
        uint256 chainId;
        address loanAsset;
    }

    /// @notice Map satellite chainId + satellite loanMarketAsset to the mapped loanAsset
    mapping(uint256 /* chainId */ => mapping(address /* satelliteLoanMarketAsset */ => LoanMarketMetadata /* LoanMarketMetadata */)) public mappedLoanAssets;

    /// @notice All loan markets in use by a particular borrower.
    mapping(address /* borrower */ => LoanMarketMetadata[] /* loanAsset */) public accountLoanMarkets;

    struct liqBorrowParams {
        address seizeToken;
        uint256 seizeTokenChainId;
        address borrower;
        address liquidator;
        uint256 repayAmount; // this is the repay amount, denominated in pToken underlying
        LoanMarketMetadata loanMarket;
    }

}


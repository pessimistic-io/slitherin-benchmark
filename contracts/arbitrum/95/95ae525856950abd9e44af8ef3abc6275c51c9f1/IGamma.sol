// SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

library GammaTypes {
    // vault is a struct of 6 arrays that describe a position a user has, a user can have multiple vaults.
    struct Vault {
        // addresses of oTokens
        address[] oTokens;
        // addresses of other ERC-20s a user has deposited as collateral in this vault
        address[] collateralAssets;
        // quantity of oTokens minted/written for each oToken address
        uint256[] shortAmounts;
        // quantity of oTokens owned and held in the vault for each oToken address
        uint256[] longAmounts;
        // quantity of ERC-20 deposited as collateral in the vault for each ERC-20 address in collateralAssets
        uint256[] collateralAmounts;
        // min strike in the vault
        uint256 minStrike;
        // max strike in the vault
        uint256 maxStrike;
        // min expiry in the vault
        uint256 minExpiry;
        // max expiry in the vault
        uint256 maxExpiry;
    }
}

interface IAddressBookGamma {
    /* Getters */

    function getOtokenImpl() external view returns (address);

    function getOtokenFactory() external view returns (address);

    function getWhitelist() external view returns (address);

    function getController() external view returns (address);

    function getOracle() external view returns (address);

    function getMarginPool() external view returns (address);

    function getMarginCalculator() external view returns (address);

    function getLiquidationManager() external view returns (address);

    function getAddress(bytes32 _id) external view returns (address);

    function getAccessKey() external view returns (address);
}

interface IOtoken {
    function underlyingAsset() external view returns (address);

    function strikeAsset() external view returns (address);

    function collateralAsset() external view returns (address);

    function strikePrice() external view returns (uint256);

    function expiryTimestamp() external view returns (uint256);

    function isPut() external view returns (bool);
}

interface IOtokenFactory {
    function getOtoken(
        address _underlyingAsset,
        address _strikeAsset,
        address _collateralAsset,
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut
    ) external view returns (address);

    function createOtoken(
        address _underlyingAsset,
        address _strikeAsset,
        address _collateralAsset,
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut
    ) external returns (address);

    function getTargetOtokenAddress(
        address _underlyingAsset,
        address _strikeAsset,
        address _collateralAsset,
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut
    ) external view returns (address);

    event OtokenCreated(
        address tokenAddress,
        address creator,
        address indexed underlying,
        address indexed strike,
        address indexed collateral,
        uint256 strikePrice,
        uint256 expiry,
        bool isPut
    );
}

interface IController {
    // possible actions that can be performed
    enum ActionType {
        OpenVault,
        MintShortOption,
        BurnShortOption,
        DepositLongOption,
        WithdrawLongOption,
        DepositCollateral,
        WithdrawCollateral,
        SettleVault,
        Redeem,
        Call,
        Liquidate,
        MintShortOptionLazy,
        WithdrawLongOptionLazy
    }

    struct ActionArgs {
        // type of action that is being performed on the system
        ActionType actionType;
        // address of the account owner
        address owner;
        // address which we move assets from or to (depending on the action type)
        address secondAddress;
        // asset that is to be transfered
        address asset;
        // index of the vault that is to be modified (if any)
        uint256 vaultId;
        // amount of asset that is to be transfered
        uint256 amount;
        // each vault can hold multiple short / long / collateral assets
        // but we are restricting the scope to only 1 of each in this version
        // in future versions this would be the index of the short / long / collateral asset that needs to be modified
        uint256 index;
        // any other data that needs to be passed in for arbitrary function calls
        bytes data;
    }

    struct RedeemArgs {
        // address to which we pay out the oToken proceeds
        address receiver;
        // oToken that is to be redeemed
        address otoken;
        // amount of oTokens that is to be redeemed
        uint256 amount;
    }

    function getPayout(
        address _otoken,
        uint256 _amount
    ) external view returns (uint256);

    function operate(
        ActionArgs[] calldata _actions
    ) external returns (bool, uint256);

    function getAccountVaultCounter(
        address owner
    ) external view returns (uint256);

    function oracle() external view returns (address);

    function getVault(
        address _owner,
        uint256 _vaultId
    ) external view returns (GammaTypes.Vault memory);

    function getVaultWithDetails(
        address _owner,
        uint256 _vaultId
    ) external view returns (GammaTypes.Vault memory, uint256);

    function getProceed(
        address _owner,
        uint256 _vaultId
    ) external view returns (uint256);

    function isSettlementAllowed(
        address _underlying,
        address _strike,
        address _collateral,
        uint256 _expiry
    ) external view returns (bool);

    function hasExpired(address _otoken) external view returns (bool);

    function setOperator(address _operator, bool _isOperator) external;

    function getOtokenIndex(
        address _owner,
        uint256 _vaultId,
        address _oToken
    ) external view returns (uint256);
}

interface IMarginCalculator {
    function getNakedMarginRequired(
        address _underlying,
        address _strike,
        address _collateral,
        uint256 _shortAmount,
        uint256 _strikePrice,
        uint256 _underlyingPrice,
        uint256 _shortExpiryTimestamp,
        uint256 _collateralDecimals,
        bool _isPut
    ) external view returns (uint256);

    function getExcessCollateral(
        GammaTypes.Vault calldata _vault
    ) external view returns (uint256 netValue, bool isExcess);
}

interface IOracle {
    function isLockingPeriodOver(
        address _asset,
        uint256 _expiryTimestamp
    ) external view returns (bool);

    function isDisputePeriodOver(
        address _asset,
        uint256 _expiryTimestamp
    ) external view returns (bool);

    function getExpiryPrice(
        address _asset,
        uint256 _expiryTimestamp
    ) external view returns (uint256, bool);

    function getDisputer() external view returns (address);

    function getPricer(address _asset) external view returns (address);

    function getPrice(address _asset) external view returns (uint256);

    function getPricerLockingPeriod(
        address _pricer
    ) external view returns (uint256);

    function getPricerDisputePeriod(
        address _pricer
    ) external view returns (uint256);

    function getChainlinkRoundData(
        address _asset,
        uint80 _roundId
    ) external view returns (uint256, uint256);

    // Non-view function

    function setExpiryPrice(
        address _asset,
        uint256 _expiryTimestamp,
        uint256 _price
    ) external;
}

interface OpynPricerInterface {
    function getPrice() external view returns (uint256);

    function getHistoricalPrice(
        uint80 _roundId
    ) external view returns (uint256, uint256);
}


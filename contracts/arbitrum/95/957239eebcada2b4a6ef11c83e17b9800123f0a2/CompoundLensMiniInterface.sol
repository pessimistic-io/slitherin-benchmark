pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./CErc20.sol";
import "./CToken.sol";
import "./EIP20Interface.sol";
import "./ComptrollerInterfaceFull.sol";

interface CompoundLensMiniInterface {
    struct CTokenMetadata {
        address ctoken;
        address underlying;
        address comptroller;
        uint ctokenDecimals;
        uint underlyingDecimals;
        string ctokenSymbol;
        string underlyingSymbol;
    }

    function cTokenMetadata(CToken cToken) external view returns (CTokenMetadata memory);

    function cTokenMetadataAll(CToken[] calldata cTokens) external view returns (CTokenMetadata[] memory);

    struct Account {
        address account;
        CToken[] markets;
    }
    struct Liquidateable {
        address account;
        ComptrollerInterfaceFull unitroller;
        CToken borrowed;
        CTokenMetadata borrowedInfo;
        uint borrowBalance;
        CToken collateral;
        CTokenMetadata collateralInfo;
    }
    // manually view
    function isLiquidationAllowed(
        address[] calldata pricesCTokens,
        uint[] calldata prices,

        CToken[] calldata distinctMarkets,
        Account[] calldata accounts,
        uint maxLiquidateable
    ) external returns (uint resultCount, Liquidateable[] memory result);

    function isLiquidationAllowedForAmount(
        address[] calldata pricesCTokens,
        uint[] calldata prices,

        address account,
        CToken borrowed, CToken collateral, uint amount
    ) external returns (bool);
}


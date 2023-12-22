// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library OptionLib {
    uint256 public constant OPTION_FIRST = 0;
    uint256 public constant OPTION_DIGITAL = OPTION_FIRST;
    uint256 public constant OPTION_AMERICAN = 1;
    uint256 public constant OPTION_TURBO = 2;
    uint256 public constant OPTION_LAST = OPTION_TURBO;

    /// @dev returns option types count
    function optionTypesCount() internal pure returns (uint256) {
        return OPTION_LAST - OPTION_FIRST + 1;
    }

    // these constants help differentiating between products
    uint256 public constant PRODUCT_FIRST = 0;
    uint256 public constant PRODUCT_BINARY = PRODUCT_FIRST;
    uint256 public constant PRODUCT_TOUCH = 1;
    uint256 public constant PRODUCT_NO_TOUCH = 2;
    uint256 public constant PRODUCT_DOUBLE_TOUCH = 3;
    uint256 public constant PRODUCT_DOUBLE_NO_TOUCH = 4;
    uint256 public constant PRODUCT_AMERICAN = 5;
    uint256 public constant PRODUCT_TURBOS = 6;
    uint256 public constant PRODUCT_LAST = PRODUCT_TURBOS;

    enum ProductKind {Digital, American, Turbo}

    function isValidProduct(ProductKind product)
    internal pure returns(bool)
    {
        return
            ProductKind.Digital == product ||
            ProductKind.American == product ||
            ProductKind.Turbo == product;
    }

    /// @dev returns product types count
    function productTypeCount() internal pure returns(uint256) {
        return PRODUCT_LAST - PRODUCT_FIRST + 1;
    }

    /// @dev options by call type: call/put/not applicable
    uint256 public constant OPTION_TYPE_NA   = 2; // not applicable
    uint256 public constant OPTION_TYPE_PUT  = 0; // PUT type
    uint256 public constant OPTION_TYPE_CALL = 1; // CALL type

    /// @dev checks if option type is a valid value
    /// @param optionType option type
    /// @return true if valid, false otherwise
    function isValidOptionType(uint256 optionType)
    internal pure returns(bool)
    {
        return optionType <=2;
    }

    /// @dev allows to differentiate between options which are put/call type and isotropic products
    function isProductCallPutType(uint256 productType) internal pure returns(bool) {
        if (productType == PRODUCT_DOUBLE_TOUCH ||
            productType == PRODUCT_DOUBLE_NO_TOUCH)
        {
            return false;
        }

        return true;
    }
}


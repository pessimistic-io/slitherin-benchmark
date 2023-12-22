// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {ERC20PresetMinterPauserUpgradeable} from "./ERC20PresetMinterPauserUpgradeable.sol";

// Interfaces
import {ISsovV3} from "./ISsovV3.sol";

// Libraries
import {Strings} from "./Strings.sol";

/**
 * @title Dopex SSOV V3 ERC20 Options Token
 */
contract SsovV3OptionsToken is ERC20PresetMinterPauserUpgradeable {
    using Strings for uint256;

    /// @dev Is this a PUT or CALL options contract
    bool public isPut;

    /// @dev The strike of the options contract
    uint256 public strike;

    /// @dev The time of expiry of the options contract
    uint256 public expiry;

    /// @dev The address of the ssov creating the options contract
    address public ssov;

    /// @dev The symbol reperesenting the underlying asset of the option
    string public underlyingSymbol;

    /// @dev The symbol representing the collateral token of the option
    string public collateralSymbol;

    /*==== INITIALIZE FUNCTION ====*/

    /**
     * @notice Initialize function, equivalent of a constructor for upgradeable contracts
     * @param _ssov The address of the ssov creating the options contract
     * @param _isPut Whether the options is a put option
     * @param _strike The amount of strike asset that will be paid out per doToken
     * @param _expiry The time at which the insurance expires
     * @param _underlyingSymbol The symbol of the underlying asset token
     * @param _collateralSymbol The symbol of the collateral token
     * @param _expirySymbol The symbol representing the expiry
     */
    function initialize(
        address _ssov,
        bool _isPut,
        uint256 _strike,
        uint256 _expiry,
        string memory _underlyingSymbol,
        string memory _collateralSymbol,
        string memory _expirySymbol
    ) public {
        require(block.timestamp < _expiry, "Can't deploy an expired contract");

        ssov = _ssov;
        underlyingSymbol = _underlyingSymbol;
        collateralSymbol = _collateralSymbol;
        isPut = _isPut;
        strike = _strike;
        expiry = _expiry;

        string memory symbol = concatenate(_underlyingSymbol, "-");
        symbol = concatenate(symbol, _expirySymbol);
        symbol = concatenate(symbol, "-");
        symbol = concatenate(symbol, (strike / 1e8).toString());
        symbol = concatenate(symbol, isPut ? "-P" : "-C");

        super.initialize("Dopex SSOV V3 Options Token", symbol);
    }

    /*==== VIEWS ====*/

    /**
     * @notice Returns true if the doToken contract has expired
     */
    function hasExpired() external view returns (bool) {
        return (block.timestamp >= expiry);
    }

    /**
     * @notice Returns the current value of an option
     */
    function optionValue() external view returns (uint256) {
        return ISsovV3(ssov).calculatePremium(strike, 1e18, expiry);
    }

    /*==== PURE FUNCTIONS ====*/

    /**
     * @notice Returns a concatenated string of a and b
     * @param _a string a
     * @param _b string b
     */
    function concatenate(string memory _a, string memory _b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(_a, _b));
    }
}


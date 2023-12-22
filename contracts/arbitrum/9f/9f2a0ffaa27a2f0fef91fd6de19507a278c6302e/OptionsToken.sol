// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {ERC20PresetMinterPauserUpgradeable} from "./ERC20PresetMinterPauserUpgradeable.sol";

// Libraries
import {Strings} from "./Strings.sol";

/**
 * @title Dopex SSOV ERC20 Options Token
 */
contract OptionsToken is ERC20PresetMinterPauserUpgradeable {
    using Strings for uint256;

    /// @dev Is this a PUT or CALL options contract
    bool public isPut;

    /// @dev The stri
    uint256 public strike;

    /// @dev The time of expiry of the options contract
    uint256 public expiry;

    /// @dev The address of the ssov creating the options contract
    address public ssov;

    /// @dev The address of the quote token for the option
    address public quoteToken;

    /// @dev The symbol of the base token for the option
    string public baseTokenSymbol;

    /*==== INITIALIZE FUNCTION ====*/

    /**
     * @notice Initialize function, equivalent of a constructor for upgradeable contracts
     * @param _ssov THe address of the ssov creating the options contract
     * @param _quoteToken The address of the quote token for the option
     * @param _isPut Whether the options is a put option
     * @param _strike The amount of strike asset that will be paid out per doToken
     * @param _expiry The time at which the insurance expires
     * @param _epoch The epoch of the ssov
     * @param _baseTokenSymbol The symbol of the base token
     */
    function initialize(
        address _ssov,
        address _quoteToken,
        bool _isPut,
        uint256 _strike,
        uint256 _expiry,
        uint256 _epoch,
        string memory _baseTokenSymbol
    ) public initializer {
        require(block.timestamp < _expiry, "Can't deploy an expired contract");

        ssov = _ssov;
        quoteToken = _quoteToken;
        isPut = _isPut;
        strike = _strike;
        expiry = _expiry;

        string memory symbol = concatenate(_baseTokenSymbol, '-EPOCH');
        symbol = concatenate(symbol, _epoch.toString());
        symbol = concatenate(symbol, '-');
        symbol = concatenate(symbol, (strike / 1e8).toString());
        symbol = concatenate(symbol, isPut ? '-P' : '-C');

        super.initialize('Dopex SSOV Options Token', symbol);
    }

    /*==== VIEWS ====*/

    /**
     * @notice Returns true if the doToken contract has expired
     */
    function hasExpired() public view returns (bool) {
        return (block.timestamp >= expiry);
    }

    /*==== PURE FUNCTIONS ====*/

    /**
     * @notice Returns a concatenated string of a and b
     * @param a string a
     * @param b string b
     */
    function concatenate(string memory a, string memory b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }
}


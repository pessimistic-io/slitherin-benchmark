// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./ISafeVault.sol";

/// @title  ISafeToken
/// @author crypt0grapher
/// @notice This contract is used as a token
interface ISafeToken is IERC20, IERC20Metadata {

    /**
    *   @notice buy SAFE tokens for given amount of USD, taxes deducted from the provided amount, SAFE is minted
    *   @param _usdToSpend number of tokens to buy, the respective amount of USD will be deducted from the user, Safe Yield token will be minted
    */
    function buySafeForExactAmountOfUSD(uint256 _usdToSpend) external returns (uint256);

    /**
    *   @notice calculate and deduct amount of USD needed to buy given amount of SAFE tokens, SAFE is minted
    *   @param _safeTokensToBuy number of tokens to buy, the respective amount of USDC will be deducted from the user, Safe Yield token will be minted
    */
    function buyExactAmountOfSafe(uint256 _safeTokensToBuy) external;

    /**
    *   @notice sell given amount of SAFE tokens for USD, taxes deducted from the user, SAFE is burned
    *   @param _safeTokensToSell number of tokens to sell, the respective amount of USDC will be returned from the user, Safe Yield token will be burned
    */
    function sellExactAmountOfSafe(uint256 _safeTokensToSell) external;

    /**
    *   @notice calculate the amount of SAFE needed to swap to get the required USD amount an sell it, SAFE is burned
    *   @param _usdToGet number of tokens to buy, the respective amount of USDC will be deducted from the user, Safe Yield token will be minted
    */
    function sellSafeForExactAmountOfUSD(uint256 _usdToGet) external;

    /**
    *   @notice admin function, currently used only to deposit 1 SAFE token to the Safe Vault to set the start price
    */
    function mint(address usr, uint256 wad) external;

    /**
    *   @notice admin function
    */
    function burn(address usr, uint256 wad) external;

    /**
    *   @notice list of wallets participating in tax distribution on top of the vault
    */
    function getWallets() external view returns (address[2] memory);

    /**
    *   @notice Usd token contract used in the protocol (USDC for now)
    */
    function usd() external view returns (IERC20);

    /**
*   @notice attached safe vault contract
    */
    function safeVault() external view returns (ISafeVault);

    /**
    *   @notice price of 1 Safe Yield token in StableCoin
    */
    function price() external view returns (uint256);
}


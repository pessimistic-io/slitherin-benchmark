// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface ISavvyPriceFeed {
    /// @notice Add priceFee by baseToken.
    /// @dev Only owner can call this function.
    /// @param baseToken The address of base token.
    /// @param priceFeed The address of priceFeed of base token.
    function setPriceFeed(address baseToken, address priceFeed) external;

    /// @notice Set priceFeed for SVY/AVAX
    /// @param newFeed The address of new priceFeed.
    function updateSvyPriceFeed(address newFeed) external;

    /// @notice Get token price from chainlink
    /// @param baseToken The address of base token.
    /// @param amount The amount of base token.
    /// @return USD amount of the base token.
    function getBaseTokenPrice(
        address baseToken,
        uint256 amount
    ) external view returns (uint256);

    /// @notice Get USD price for SVY/AVAX
    /// @dev Explain to a developer any extra details
    /// @return Return USD price for SVY/AVAX
    function getSavvyTokenPrice() external view returns (uint256);
}


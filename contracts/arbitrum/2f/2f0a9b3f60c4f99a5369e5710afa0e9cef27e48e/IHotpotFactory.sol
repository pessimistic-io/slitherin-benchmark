// SPDX-License-Identifier: MIT

import "./GovernorLib.sol";

pragma solidity ^0.8.0;

interface IHotpotFactory {
    /**
     * Token information struct, containing details of the token being deployed.
     */
    struct TokenInfo {
        /**
         * Token type.
         */
        string tokenType;
        /**
         * Bonding curve type.
         */
        string bondingCurveType;
        /**
         * Token name.
         */
        string name;
        /**
         * Token symbol.
         */
        string symbol;
        /**
         * Token metadata.
         */
        string metadata;
        /**
         * Address of the project administrator.
         */
        address projectAdmin;
        /**
         * Address of the project treasury.
         */
        address projectTreasury;
        /**
         * Project mint tax rate.
         */
        uint256 projectMintTax;
        /**
         * Project burn tax rate.
         */
        uint256 projectBurnTax;
        /**
         * Address of the raising token.
         */
        address raisingTokenAddr;
        /**
         * Data bytes.
         */
        bytes data;
    }

    /**
     * Deploy a new token with the specified `TokenInfo`.
     *
     * @param token The information of the token to be deployed
     * @param mintfirstAmount The first amount of the token to be minted.
     */
    function deployToken(TokenInfo calldata token, uint256 mintfirstAmount) external payable;

    /**
     * Creates a governor for a token with the specified information.
     *
     * @param proxyAddr  the proxy address of the token
     * @param token the token information in the form of a GovernorLib.GovInfo struct.
     */
    function createGovernorForToken(address proxyAddr, GovernorLib.GovInfo calldata token) external;

    /**
     * Add an implementation of a bonding curve type to the Hotpot platform.
     *
     * @param impl the implementation address to be added.
     */
    function addBondingCurveImplement(address impl) external;

    /**
     * Updates the implementation of a Hotpot token.
     *
     * @param tokenType the type of token
     * @param impl updates the implementation of the Hotpot.
     */
    function updateHotpotImplement(string calldata tokenType, address impl) external;

    /**
     * Retrieve the implementation of a specified token type from the Hotpot platform.
     *
     * @param tokenType the type of token
     * @return impl the implementation address.
     */
    function getHotpotImplement(string memory tokenType) external view returns (address impl);

    /**
     * Retrieve the implementation of a specified bonding curve type.
     *
     * @param bondingCurveType the type of bonding curve
     * @return impl the implementation address.
     */
    function getBondingCurveImplement(string calldata bondingCurveType) external view returns (address impl);

    /**
     * Set the platform's tax rate for minting and burning tokens.
     * @param platformMintTax the platform's tax rate for minting tokens.
     * @param platformBurnTax the platform's tax rate for burning tokens.
     */
    function setPlatformTaxRate(uint256 platformMintTax, uint256 platformBurnTax) external;

    /**
     * Retrieve the platform's tax rate for minting and burning tokens.
     * @return platformMintTax the platform's tax rate for minting tokens.
     * @return platformBurnTax the platform's tax rate for burning tokens.
     */
    function getTaxRateOfPlatform() external view returns (uint256 platformMintTax, uint256 platformBurnTax);

    /**
     * Get the number of tokens deployed on the Hotpot platform.
     * @return len the number of tokens.
     */
    function getTokensLength() external view returns (uint256 len);

    /**
     * Get the address of a deployed token by its index.
     * @param index the index of the token.
     * @return addr the address of the deployed token.
     */
    function getToken(uint256 index) external view returns (address addr);

    /**
     * Get the address of the platform administrator.
     * @return the address of the platform administrator.
     */
    function getPlatformAdmin() external view returns (address);

    /**
     * Get the address of the platform treasury.
     * @return the address of the platform treasury.
     */
    function getPlatformTreasury() external view returns (address);

    /**
     * Declare a doomsday event for a token.
     * @param proxyAddress the address of the token's proxy.
     */
    function declareDoomsday(address proxyAddress) external;

    /**
     * Pause a token.
     * @param proxyAddress the address of the token's proxy.
     */
    function pause(address proxyAddress) external;

    /**
     * Unpause a token.
     * @param proxyAddress the address of the token's proxy.
     */
    function unpause(address proxyAddress) external;

    /**
     * Request an upgrade for a token's implementation.
     * @param proxyAddress the address of the token's proxy.
     * @param data additional data for the upgrade request.
     */
    function requestUpgrade(address proxyAddress, bytes calldata data) external;

    /**
     * Reject an upgrade request for a token.
     * @param proxyAddress the address of the token's proxy.
     * @param reason the reason for rejection.
     */
    function rejectUpgrade(address proxyAddress, string calldata reason) external;

    /**
     * Upgrade a token's implementation.
     * @param proxyAddress the address of the token's proxy.
     */
    function upgradeTokenImplement(address proxyAddress) external payable;

    function getTokenHooks(address token) external view returns (address[] memory hooks);

    /**
     *  whitelist/blacklist a hook contract
     *  @param hook the address of the hook contract
     *  @param flag true for whitelist, false for blacklist
     */
    function setHook(address hook, bool flag) external;

    function addHookForToken(address token, address hook, bytes calldata data) external;

    function updateHookForToken(address token, address[] calldata hooks, bytes[] calldata datas) external;

    function removeHookForToken(address token, address hook) external;

    function removeAllHookForToken(address token) external;

    event LogTokenDeployed(string tokenType, string bondingCurveType, uint256 tokenId, address deployedAddr);

    event LogTokenUpgradeRequested(
        address proxyAddress,
        uint256 timelock,
        address implementAddr,
        address requester,
        bytes data
    );
    event LogTokenUpgradeRejected(address proxyAddress, address rejecter, string reason);
    event LogTokenImplementUpgraded(address proxyAddress, string tokenType, address implementAddr);

    event LogTokenTypeImplAdded(string tokenType, address impl);

    event LogBondingCurveTypeImplAdded(string tokenType, address impl);

    event LogPlatformAdminChanged(address newAccount);

    event LogPlatformTreasuryChanged(address newAccount);
    event LogRouteChanged(address newRoute);

    event LogPlatformTaxChanged();
}


// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {BinaryVaultDataType} from "./BinaryVaultDataType.sol";

interface IBinaryVaultBaseFacet {
    function whitelistMarkets(address market)
        external
        view
        returns (bool, uint256);

    function setWhitelistMarket(
        address market,
        bool whitelist,
        uint256 exposureBips
    ) external;

    function totalShareSupply() external view returns (uint256);

    function totalDepositedAmount() external view returns (uint256);

    function setWhitelistUser(address user, bool value) external;

    function enableUseWhitelist(bool value) external;

    function setCreditToken(address) external;

    function underlyingTokenAddress() external view returns (address);

    function getCreditToken() external view returns (address);
}


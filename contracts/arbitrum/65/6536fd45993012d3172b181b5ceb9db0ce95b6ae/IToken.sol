// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20MetadataUpgradeable.sol";

interface IToken is IERC20MetadataUpgradeable {

    struct Taxes {
        uint256 marketing;
    }

    struct Airdrop {
        address wallet;
        uint256 amount;
    }

    struct TokenData {
        string name;
        string symbol;
        uint8 decimals;
        uint256 supply;
        uint256 maxTx;
        uint256 maxWallet;
        address routerAddress;
        Taxes buyTax;
        Taxes sellTax;
        address marketingWallet;
        Airdrop airdrop1;
        Airdrop airdrop2;
        Airdrop airdrop3;
        Airdrop airdrop4;
        Airdrop airdrop5;
        uint256 tokensInCaPercent;
        string telegramId;
    }

    function initialize(TokenData memory tokenData) external;

    function updateExcludedFromFees(address _address, bool state) external;
    function excludedFromFees(address _address) external view returns (bool);

    function getOwner() external view returns (address);
}


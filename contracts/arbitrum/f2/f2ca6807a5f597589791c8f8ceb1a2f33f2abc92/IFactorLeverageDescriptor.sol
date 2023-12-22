// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.17;

interface IFactorLeverageDescriptor {
    struct TokenURIParams {
        uint256 id;
        string name;
        string description;
        address assetToken;
        address debtToken;
        uint256 assetAmount;
        uint256 debtAmount;
    }

    function constructTokenURI(TokenURIParams calldata params) external view returns (string memory);
}


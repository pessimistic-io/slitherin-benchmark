//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IOSBFactory {
    function create(bool _isSingle, string memory _baseUri, string memory _name, string memory _symbol, address _royaltyReceiver, uint96 _royaltyFeeNumerator) external returns(TokenInfo memory);
}

struct TokenInfo {
    address owner;
    address token;
    address receiverRoyaltyFee;
    uint96 percentageRoyaltyFee;
    string baseURI;
    string name;
    string symbol;
    bool isSingle;
}

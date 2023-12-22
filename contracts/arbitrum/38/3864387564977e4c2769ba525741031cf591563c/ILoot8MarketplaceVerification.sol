// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ILoot8Marketplace.sol";

interface ILoot8MarketplaceVerification {

    event ValidatorSet(address _validator, address _newValidator);

    function setValidator(address _newValidator) external;

    function getPatronCurrentNonce(address _patron) external view returns(uint256);

    function verify(
        address _patron,
        address _passport,
        address _collection,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        string memory _action,
        ILoot8Marketplace.ListingType _listingType,
        string memory _message,
        uint256 _expiry,
        bytes memory _signature
    ) external view returns (bool);

    function verifyAndUpdateNonce(
        address _patron,
        address _passport,
        address _collection,
        uint256 _tokenId,
        address _paymentToken,
        uint256 _price,
        string memory _action,
        ILoot8Marketplace.ListingType _listingType,
        string memory _message,
        uint256 _expiry,
        bytes memory _signature
    ) external returns (bool);    
}


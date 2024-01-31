// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IERC2981.sol";
import "./IERC721A.sol";
import "./IOperatorFilter.sol";
import "./ISignatureVerifier.sol";
import "./ITokenSale.sol";

interface ISomewhereNowhere is
    IERC2981,
    IERC721A,
    IOperatorFilter,
    ISignatureVerifier,
    ITokenSale
{
    error MetadataContractAddressIsZeroAddress();

    error NotEnoughPaymentSent();

    error SenderIsNotOrigin();

    error TokenDoesNotExist();

    event CreatorFeeInfoUpdated(
        address indexed receiver,
        uint96 feeBasisPoints
    );

    event MetadataContractAddressUpdated(
        address indexed metadataContractAddress
    );

    function mintReserve(address[] calldata addresses, uint256 quantity)
        external;

    function setCreatorFeeInfo(address receiver, uint96 feeBasisPoints)
        external;

    function setMetadataContractAddress(address metadataContractAddress)
        external;

    function getMetadataContractAddress() external view returns (address);

    function supportsInterface(bytes4 interfaceId)
        external
        view
        override(IERC165, IERC721A)
        returns (bool);
}


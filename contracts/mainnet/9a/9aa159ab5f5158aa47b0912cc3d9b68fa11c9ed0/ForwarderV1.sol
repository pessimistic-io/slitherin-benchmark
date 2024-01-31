// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "./AccessControl.sol";
import "./IERC721.sol";
import "./Address.sol";

error ZeroAddress();

enum MintRequestErrorType {
    ValueIncorrect,
    CollectionIncorrect
}

error InvalidMintRequest(MintRequestErrorType errorType);

struct MintRequest {
    // The address that requested the mint.
    address requestFrom;

    // The contract that we are sending the mint request to.
    address payable targetCollection;

    // The value to send along to the `toCollection` in the mint request.
    uint256 value;

    // The data to send along to the `toCollection` in the mint request.
    bytes data;

    // A nonce that lets our system deduplicate requests.
    uint256 nonce;
}

contract ForwarderV1 is AccessControl {
    using Address for address payable;

    address payable internal _treasury;

    bytes32 public constant MINT_FORWARDER_ROLE = keccak256("MINT_FORWARDER_ROLE");
    bytes32 public constant TRANSFERER_ROLE = keccak256("TRANSFERER_ROLE");

    constructor(address payable treasury) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINT_FORWARDER_ROLE, msg.sender);
        _grantRole(TRANSFERER_ROLE, msg.sender);

        _treasury = treasury;
    }

    function forwardMint(
        MintRequest calldata mintRequest
    ) external payable onlyRole(MINT_FORWARDER_ROLE) {
        if (mintRequest.value != msg.value) {
            revert InvalidMintRequest(MintRequestErrorType.ValueIncorrect);
        }
        if (address(this) == mintRequest.targetCollection) {
            revert InvalidMintRequest(MintRequestErrorType.CollectionIncorrect);
        }

        mintRequest.targetCollection.functionCallWithValue(
            mintRequest.data,
            mintRequest.value
        );
    }

    function safeTransferNFT(
        IERC721 collectionContract,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public onlyRole(TRANSFERER_ROLE) {
        collectionContract.safeTransferFrom(
            address(this), to, tokenId, data
        );
    }

    function safeTransferNFT(
        IERC721 collectionContract,
        address to,
        uint256 tokenId
    ) public onlyRole(TRANSFERER_ROLE) {
        safeTransferNFT(collectionContract, to, tokenId, "");
    }

    function transferNFT(
        IERC721 collectionContract,
        address to,
        uint256 tokenId
    ) public onlyRole(TRANSFERER_ROLE) {
        collectionContract.transferFrom(
            address(this), to, tokenId
        );
    }

    // No need to protect this with a RBAC because it can only withdraw to our
    // treasury address, and setting that address is protected.
    function withdraw() public {
        uint256 balance = address(this).balance;
        (bool success, bytes memory result) = payable(_treasury).call{
            value: balance
        }("");
        require(success, string(result));
    }

    function getTreasury() external view returns (address payable) {
        return _treasury;
    }

    function setTreasury(address payable treasury) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury == address(0)) revert ZeroAddress();
        _treasury = treasury;
    }
}


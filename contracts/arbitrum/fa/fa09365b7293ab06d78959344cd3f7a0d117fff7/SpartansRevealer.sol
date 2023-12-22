//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import "./FisherYatesRangeValueGeneratorInitializable.sol";
import "./RevealedSpartans.sol";
import "./IERC721.sol";

contract SpartansRevealer is FisherYatesRangeValueGeneratorInitializable {
    error MaxLimitRevealExceeded();
    error OnlyApprovalOrOwnerAccess();
    uint256 public constant MAX_PER_TRANSACTION = 10;
    address public constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    IERC721 public immutable collectionToReveal;
    RevealedSpartans public immutable collection;
    uint256 public immutable maxSupply;
    address private _lastInteracted;

    constructor(
        address treasuryWallet_,
        uint96 royaltyNumerator_,
        string memory name_,
        string memory symbol_,
        IERC721 collectionToReveal_,
        address _owner,
        uint256 maxSupply_,
        string memory baseTokenURI_,
        string memory contractURI_
    ) FisherYatesRangeValueGeneratorInitializable(_owner, maxSupply_) {
        collection = new RevealedSpartans(
            treasuryWallet_,
            royaltyNumerator_,
            name_,
            symbol_,
            address(this),
            baseTokenURI_,
            contractURI_
        );
        collectionToReveal = collectionToReveal_;
        maxSupply = maxSupply_;
    }

    function foo() external pure {}

    function reveal(uint256[] calldata tokens) external isInitialized {
        uint256 length = tokens.length;
        if (length > MAX_PER_TRANSACTION) {
            revert MaxLimitRevealExceeded();
        }
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokens[i];
            address tokenOwner = collectionToReveal.ownerOf(tokenId);
            if (!canReveal(tokenId, msg.sender)) {
                revert OnlyApprovalOrOwnerAccess();
            }
            collectionToReveal.safeTransferFrom(
                tokenOwner,
                DEAD_ADDRESS,
                tokenId
            );
            uint256 randomValue = rand();
            collection.mint(tokenOwner, randomValue);
        }
    }

    function canReveal(
        uint256 tokenId,
        address addr
    ) public view returns (bool) {
        address tokenOwner = collectionToReveal.ownerOf(tokenId);
        return
            tokenOwner == addr ||
            collectionToReveal.getApproved(tokenId) == addr ||
            collectionToReveal.isApprovedForAll(tokenOwner, addr);
    }
}


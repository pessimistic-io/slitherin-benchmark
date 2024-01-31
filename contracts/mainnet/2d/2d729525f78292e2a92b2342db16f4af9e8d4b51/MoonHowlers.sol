// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721A, IERC721A, ERC721AQueryable} from "./ERC721AQueryable.sol";
import {ERC721ABurnable} from "./ERC721ABurnable.sol";
import {IERC721} from "./IERC721.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {Strings} from "./Strings.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC2981, ERC2981} from "./ERC2981.sol";
import {DefaultOperatorFilterer} from "./DefaultOperatorFilterer.sol";
import {NativeMetaTransaction} from "./NativeMetaTransaction.sol";

/**
 * @title MoonHowlers
 * @custom:website https://moonshiners.wtf/
 * @author @MoonShinersNFT
 */
contract MoonHowlers is
    DefaultOperatorFilterer,
    ERC2981,
    NativeMetaTransaction,
    ERC721AQueryable,
    ERC721ABurnable,
    Ownable,
    ReentrancyGuard
{
    using Strings for uint256;

    struct MintState {
        uint256 liveAt;
        uint256 expiresAt;
        uint256 totalSupply;
    }

    address public constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    // @dev Base uri for the nft
    string private baseURI = "ipfs://cid/";

    /// @notice Live timestamp
    uint256 public liveAt = 0;

    /// @notice Expires timestamp
    uint256 public expiresAt = 1681844400;

    /// @notice Core Pass contract
    IERC721 public moonshinersContract;

    /// @notice Passes contract
    IERC721 public moonshineContract;

    constructor(
        address _moonshinersContract,
        address _moonshineContract
    ) ERC721A("MoonHowlers", "MOONHW") {
        _setDefaultRoyalty(_msgSenderERC721A(), 1000);
        moonshinersContract = IERC721(_moonshinersContract);
        moonshineContract = IERC721(_moonshineContract);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /**
     * @notice Sets the base URI of the NFT
     * @param _baseURI A base uri
     */
    function setBaseURI(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    /**************************************************************************
     * Minting
     *************************************************************************/

    /**
     * @dev Howlers exchange mint
     * @param _moonshinersTokenIds The moonshiners token ids
     * @param _moonshineTokenIds The moonshine token ids
     */
    function mint(
        uint256[] calldata _moonshinersTokenIds,
        uint256[] calldata _moonshineTokenIds
    ) external {
        require(isLive(), "Mint not live.");
        require(
            _moonshinersTokenIds.length > 1,
            "Must have a multiple of 2 moonshiners"
        );
        require(
            _moonshineTokenIds.length > 0,
            "Must have at least 1 moonshine per 2 moonshiners"
        );

        address sender = _msgSenderERC721A();

        // Exchange moonshiners
        for (uint256 i = 0; i < _moonshinersTokenIds.length; i++) {
            moonshinersContract.safeTransferFrom(
                sender,
                DEAD_ADDRESS,
                _moonshinersTokenIds[i]
            );
        }

        // Exchange moonshine
        for (uint256 j = 0; j < _moonshineTokenIds.length; j++) {
            moonshineContract.safeTransferFrom(
                sender,
                DEAD_ADDRESS,
                _moonshineTokenIds[j]
            );
        }

        // Mint howlers equal to mutations
        _mint(sender, _moonshineTokenIds.length);
    }

    /// @dev Check if mint is live
    function isLive() public view returns (bool) {
        return block.timestamp > liveAt && block.timestamp < expiresAt;
    }

    /// @notice Returns current mint state for a particular address
    function getMintState() external view returns (MintState memory) {
        return
            MintState({
                liveAt: liveAt,
                expiresAt: expiresAt,
                totalSupply: totalSupply()
            });
    }

    /**
     * @notice Returns the URI for a given token id
     * @param _tokenId A tokenId
     */
    function tokenURI(
        uint256 _tokenId
    ) public view override(IERC721A, ERC721A) returns (string memory) {
        if (!_exists(_tokenId)) revert OwnerQueryForNonexistentToken();
        return
            string(
                abi.encodePacked(baseURI, Strings.toString(_tokenId), ".json")
            );
    }

    /**************************************************************************
     * Admin
     *************************************************************************/

    /**
     * @notice Sets timestamps for live and expires timeframe
     * @param _liveAt A unix timestamp for live date
     * @param _expiresAt A unix timestamp for expiration date
     */
    function setMintWindow(
        uint256 _liveAt,
        uint256 _expiresAt
    ) external onlyOwner {
        liveAt = _liveAt;
        expiresAt = _expiresAt;
    }

    /**
     * @notice Changes the contract defined royalty
     * @param _receiver - The receiver of royalties
     * @param _feeNumerator - The numerator that represents a percent out of 10,000
     */
    function setDefaultRoyalty(
        address _receiver,
        uint96 _feeNumerator
    ) public onlyOwner {
        _setDefaultRoyalty(_receiver, _feeNumerator);
    }

    /// @notice Withdraws funds from contract
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = _msgSenderERC721A().call{value: balance}("");
        require(success, "Unable to withdraw ETH");
    }

    /**
     * @dev Admin mint function
     * @param _to The address to mint to
     * @param _amount The amount to mint
     */
    function adminMint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    /**************************************************************************
     * Royalties
     *************************************************************************/

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC721A, ERC721A, ERC2981) returns (bool) {
        return
            ERC721A.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(IERC721A, ERC721A) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    )
        public
        payable
        override(IERC721A, ERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(IERC721A, ERC721A) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(IERC721A, ERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override(IERC721A, ERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}


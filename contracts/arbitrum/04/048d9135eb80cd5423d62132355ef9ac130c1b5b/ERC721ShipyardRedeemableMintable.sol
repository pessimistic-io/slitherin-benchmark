// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC165} from "./interfaces_IERC165.sol";
import {ERC721ConduitPreapproved_Solady} from "./ERC721ConduitPreapproved_Solady.sol";
import {ConsiderationItem} from "./ConsiderationStructs.sol";
import {Ownable} from "./Ownable.sol";
import {ERC7498NFTRedeemables} from "./ERC7498NFTRedeemables.sol";
import {CampaignParams} from "./RedeemablesStructs.sol";
import {IRedemptionMintable} from "./IRedemptionMintable.sol";
import {ERC721ShipyardRedeemable} from "./ERC721ShipyardRedeemable.sol";
import {IRedemptionMintable} from "./IRedemptionMintable.sol";
import {TraitRedemption} from "./RedeemablesStructs.sol";

contract ERC721ShipyardRedeemableMintable is
    ERC721ShipyardRedeemable,
    IRedemptionMintable
{
    /// @dev Revert if the sender of mintRedemption is not this contract.
    error InvalidSender();

    /// @dev The preapproved address.
    address internal _preapprovedAddress;

    /// @dev The preapproved OpenSea conduit address.
    address internal immutable _CONDUIT =
        0x1E0049783F008A0085193E00003D00cd54003c71;

    /// @dev The next token id to mint.
    uint256 _nextTokenId = 1;

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721ShipyardRedeemable(name_, symbol_) {}

    function mintRedemption(
        uint256 /* campaignId */,
        address recipient,
        ConsiderationItem[] calldata /* consideration */,
        TraitRedemption[] calldata /* traitRedemptions */
    ) external {
        if (msg.sender != address(this)) {
            revert InvalidSender();
        }
        // Increment nextTokenId first so more of the same token id cannot be minted through reentrancy.
        ++_nextTokenId;

        _mint(recipient, _nextTokenId - 1);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721ShipyardRedeemable) returns (bool) {
        return
            interfaceId == type(IRedemptionMintable).interfaceId ||
            ERC721ShipyardRedeemable.supportsInterface(interfaceId);
    }

    /**
     * @notice Set the preapproved address. Only callable by the owner.
     *
     * @param newPreapprovedAddress The new preapproved address.
     */
    function setPreapprovedAddress(
        address newPreapprovedAddress
    ) external onlyOwner {
        _preapprovedAddress = newPreapprovedAddress;
    }

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets
     *      of `owner`.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(
        address owner,
        address operator
    ) public view virtual override returns (bool) {
        if (operator == _CONDUIT || operator == _preapprovedAddress) {
            return true;
        }
        return super.isApprovedForAll(owner, operator);
    }

    /**
     * @notice Burns `tokenId`. The caller must own `tokenId` or be an
     *         approved operator.
     *
     * @param tokenId The token id to burn.
     */
    // solhint-disable-next-line comprehensive-interface
    // TODO: does this need permissions or to check approvals?
    // I didn't see anything on the internal implement of _burn.
    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    // TODO: For testing
    function mint(address to, uint256 tokenId) public onlyOwner {
        _mint(to, tokenId);
    }
}


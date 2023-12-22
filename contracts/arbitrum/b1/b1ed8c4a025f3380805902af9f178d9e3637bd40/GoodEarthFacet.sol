// SPDX-License-Identifier: None
pragma solidity 0.8.18;
import {IERC2981} from "./IERC2981.sol";
import {UintUtils} from "./UintUtils.sol";
import {SolidStateERC1155} from "./SolidStateERC1155.sol";
import {ERC1155MetadataStorage} from "./ERC1155MetadataStorage.sol";
import {ERC1155Metadata} from "./ERC1155Metadata.sol";
import {IERC1155Metadata} from "./IERC1155Metadata.sol";
import {WithStorage, WithModifiers, TokensConstants} from "./GoodEarthAppStorage.sol";
import "./LibPrices.sol";
import {LibAccessControl} from "./LibAccessControl.sol";
import {LibToken} from "./LibToken.sol";
import {IERC165} from "./IERC165.sol";

import {IERC1155} from "./IERC1155.sol";
import {ERC1155Base} from "./ERC1155Base.sol";
import {ERC165Base} from "./ERC165Base.sol";
import {LibDiamond} from "./LibDiamond.sol";
import "./EnumerableSet.sol";

contract GoodEarthFacet is SolidStateERC1155, IERC2981, WithStorage, WithModifiers {
    using UintUtils for uint256;
    string public name = 'Kaiju Cards NFTs';
    event Unlocked(uint256 tokenId);
    event Locked(uint256 tokenId);

    // *****NFT Functions*****
    function contractURI() public view returns (string memory) {
        return _constants().contractUri;
    }

    function setContractUri(string memory contractUri) public ownerOnly {
        _constants().contractUri = contractUri;
    }

    function getBaseUri() public view returns (string memory) {
        return _constants().baseUri;
    }

    function setBaseUri(string memory baseUri) public ownerOnly {
        _constants().baseUri = baseUri;
    }

    function uri(
        uint256 tokenId
    )
        public
        view
        override(ERC1155Metadata, IERC1155Metadata)
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    _constants().baseUri,
                    tokenId.toString(),
                    '.json'
                )
            );
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override pausable {
        for (uint256 i; i < ids.length; i++) {
            uint256 tokenId = ids[i];

            if (from != address(0)) {
                require(
                    _token().tradingIsEnabled,
                    'Trading is disabled'
                );
                require(
                    _token().isTokenTradable[tokenId],
                    'Token locked for trading'
                );
            } else {
                _token().isTokenTradable[tokenId] = true;
            }

            _token().ownerOf[tokenId] = to;
        }

        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function royaltyInfo(
        uint256,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        return (
            _token().royaltiesRecipient,
            (salePrice * _token().royaltiesPercentage) / 10000
        );
    }

    function setRoyaltiesRecipient(address recipient) external ownerOnly {
        _token().royaltiesRecipient = recipient;
    }

    function setRoyaltiesPercentage(uint256 percentage) external ownerOnly {
        require(percentage <= 10000, 'Royalties percentage too high');
        _token().royaltiesPercentage = percentage;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Base, IERC165) returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        return (interfaceId == type(IERC2981).interfaceId ||
            interfaceId == 0xd9b67a26 ||
            interfaceId == type(IERC165).interfaceId ||
            super.supportsInterface(interfaceId)) ||
            ds.supportedInterfaces[interfaceId];
    }

    function addSupportedInterface(
        bytes4 interfaceId
    ) external ownerOnly {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[interfaceId] = true;
    }

    function isApprovedForAll(
        address account,
        address operator
    ) public view virtual override(ERC1155Base, IERC1155) returns (bool) {
        /** TODO - @dev Standard ERC1155 approvals. */
        return super.isApprovedForAll(account, operator);
    }

    function _generateNftTokenId() internal returns (uint256) {
        return _token().nftIndex++;
    }

    function getRequestedNftActionsBalance(address account) external view returns (uint16) {
        return _token().requestedNftActions[account];
    }

    function requestNftAction(uint16 quantity) external payable pausable {
        uint256 totalPrice = _constants().nftActionPrice * quantity;
        require(
            msg.value >= totalPrice,
            'Incorrect amount of ETH sent'
        );
        _token().requestedNftActions[msg.sender] += quantity;
    }

    //*****Admin Functions*****
    function mintToken(
        uint8 amount,
        address to
    ) external pausable roleOnly(LibAccessControl.Roles.MINTER) {
        require(_token().requestedNftActions[to] >= amount, 'Not enough requested NFT conversions');

        uint256[] memory mintedIds = new uint256[](amount);
        uint256[] memory amounts = new uint256[](amount);

        for (uint8 i = 0; i < amount; i++) {
            uint256 tokenId = _generateNftTokenId();
            mintedIds[i] = tokenId;
            amounts[i] = 1;
            _token().requestedNftActions[to]--;
        }

        _safeMintBatch(to, mintedIds, amounts, '');
    }

    function getNftActionPrice() external view returns (uint256) {
        return _constants().nftActionPrice;
    }

    function setNftActionPrice(uint256 price) external ownerOnly {
        _constants().nftActionPrice = price;
    }

    function getIsAddressMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(_access().rolesByAddress[account], uint256(LibAccessControl.Roles.MINTER));
    }

    function setMinterAddress(address account) public ownerOnly {
        EnumerableSet.add(_access().rolesByAddress[account], uint256(LibAccessControl.Roles.MINTER));
    }

    function removeMinterAddress(address account) public ownerOnly {
        EnumerableSet.remove(_access().rolesByAddress[account], uint256(LibAccessControl.Roles.MINTER));
    }

    function lockNft(uint256 id) public pausable {
        require(balanceOf(msg.sender, id) != 0, 'Does not own token');
        require(_token().isTokenTradable[id], 'Already locked');

        _token().isTokenTradable[id] = false;
        emit Locked(id);
    }

    function unlockNft(uint256 id) public pausable {
        require(balanceOf(msg.sender, id) != 0, 'Does not own token');
        require(!_token().isTokenTradable[id], 'Already unlocked');
        _token().isTokenTradable[id] = true;
        emit Unlocked(id);
    }

    /**TODO */
    function isLocked(uint256 id) external view returns (bool) {
        return !_token().isTokenTradable[id];
    }

    function getOwnerOf(uint256 id) external view returns (address) {
        return _token().ownerOf[id];
    }

    function setTradingIsEnabled(bool enabled) public ownerOnly {
        _token().tradingIsEnabled = enabled;
    }

    function getTradingIsEnabled() public view returns (bool) {
        return _token().tradingIsEnabled;
    }

    function setMintingIsEnabled(bool enabled) public ownerOnly {
        _token().mintingIsEnabled = enabled;
    }

    function getMintingIsEnabled() public view returns (bool) {
        return _token().mintingIsEnabled;
    }

    function getContractOwner() public view returns (address) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.contractOwner;
    }

    function setContractOwner(address newOwner) public ownerOnly {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.contractOwner = newOwner;
    }

    function unlockTokens(uint256 fromTokenId, uint256 toTokenId) public ownerOnly {
        for (uint256 i = fromTokenId; i < toTokenId; i++) {
            _token().isTokenTradable[i] = true;
        }
    }
}


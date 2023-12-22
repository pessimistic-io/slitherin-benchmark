// SPDX-License-Identifier: None
pragma solidity 0.8.18;
import {IERC2981} from "./IERC2981.sol";
import {UintUtils} from "./UintUtils.sol";
import {SolidStateERC1155} from "./SolidStateERC1155.sol";
import {ERC1155MetadataStorage} from "./ERC1155MetadataStorage.sol";
import {ERC1155Metadata} from "./ERC1155Metadata.sol";
import {IERC1155Metadata} from "./IERC1155Metadata.sol";
import {WithStorage, WithModifiers, TokensConstants} from "./ItemsLibAppStorage.sol";
import "./LibPrices.sol";
import {LibAccessControl} from "./LibAccessControl.sol";
import {LibToken} from "./LibToken.sol";
import {IERC165} from "./IERC165.sol";

import {IERC1155} from "./IERC1155.sol";
import {ERC1155Base} from "./ERC1155Base.sol";
import {ERC165Base} from "./ERC165Base.sol";
import {LibDiamond} from "./LibDiamond.sol";
import "./EnumerableSet.sol";

contract ItemsFacet is SolidStateERC1155, IERC2981, WithStorage, WithModifiers {
    using UintUtils for uint256;
    string public name = 'Kaiju Cards Item NFTs';
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
            LibToken.ItemType itemType = _token().itemTypeByTokenId[ids[i]];

            if (itemType == LibToken.ItemType.EQUIPMENT) {
                if (from != address(0)) {
                    require(
                        _token().equipmentTradingIsEnabled,
                        'Equipment trading is disabled'
                    );
                    require(
                        _token().isTokenTradable[ids[i]],
                        'Token locked for trading'
                    );
                } else {
                    _token().isTokenTradable[ids[i]] = true;
                    _token().numTradesSinceTransmog[i] = 0;
                }
            } else if (itemType == LibToken.ItemType.CHEST) {
                if (from != address(0)) {
                    if (to != address(0)) {
                        require(
                            _token().chestTradingIsEnabled,
                            'Chest trading is disabled'
                        );
                        require(
                            _token().isTokenTradable[ids[i]],
                            'Token locked for trading'
                        );
                    }
                } else {
                    _token().isTokenTradable[ids[i]] = true;
                    _token().numTradesSinceTransmog[i] = 0;
                }
            }

            // this should reset to 0 when transmogged
            bool tokenReachedTransmogTradeLimit = _token()
                .numTradesSinceTransmog[i] >=
                _constants().NUM_TRADES_ALLOWED_AFTER_TRANSMOG;

            if (tokenReachedTransmogTradeLimit == true) {
                revert('Token reached transmog limit');
            } else {
                _token().numTradesSinceTransmog[i]++;
            }

            _token().ownerOf[ids[i]] = to;
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
        return _token().itemsIndex++;
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
    function mintGameItem(
        uint8 amount,
        address to,
        LibToken.ItemType itemType
    ) external pausable roleOnly(LibAccessControl.Roles.MINTER) {
        require(_token().requestedNftActions[to] >= amount, 'Not enough requested NFT conversions');
        if (itemType == LibToken.ItemType.EQUIPMENT) {
            require(
                _token().equipmentMintingIsEnabled,
                'Equipment minting is not yet available'
            );
        } else if (itemType == LibToken.ItemType.CHEST) {
            require(
                _token().chestMintingIsEnabled,
                'Chest minting is not yet available'
            );
        } else {
            revert('Invalid item type');
        }

        uint256[] memory mintedIds = new uint256[](amount);
        uint256[] memory amounts = new uint256[](amount);

        for (uint8 i = 0; i < amount; i++) {
            uint256 tokenId = _generateNftTokenId();
            mintedIds[i] = tokenId;
            amounts[i] = 1;
            _token().itemTypeByTokenId[tokenId] = itemType;
            _token().requestedNftActions[to]--;
        }

        _safeMintBatch(to, mintedIds, amounts, '');
    }


    function openTreasureChest(
        uint256 tokenId,
        address receiver
    ) external pausable roleOnly(LibAccessControl.Roles.MINTER) {
        require(_token().requestedNftActions[receiver] >= 1, 'Not enough requested NFT conversions');
        require(balanceOf(receiver, tokenId) > 0, 'Does not own token anymore');
        require(
            _token().itemTypeByTokenId[tokenId] == LibToken.ItemType.CHEST,
            'Item is not a chest'
        );

        super._burn(receiver, tokenId, 1);
        _token().requestedNftActions[receiver]--;
    }

    function setNftActionPrice(uint256 price) external ownerOnly {
        _constants().nftActionPrice = price;
    }

    function getItemType(uint256 id) external view returns (LibToken.ItemType) {
        return _token().itemTypeByTokenId[id];
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

    //TODO make only owner or admin?
    function unlockNft(uint256 id) public pausable {
        require(balanceOf(msg.sender, id) != 0, 'Does not own token');
        require(!_token().isTokenTradable[id], 'Already unlocked');
        _token().isTokenTradable[id] = true;
        emit Unlocked(id);
    }

    /**TODO */
    function isLocked(uint256 id) external view returns (bool) {
        LibToken.ItemType itemType = _token().itemTypeByTokenId[id];
        if (itemType == LibToken.ItemType.EQUIPMENT && !_token().equipmentTradingIsEnabled) {
            return true;
        } else if (itemType == LibToken.ItemType.CHEST && !_token().chestTradingIsEnabled) {
            return true;
        }

        return !_token().isTokenTradable[id];
    }

    function getOwnerOf(uint256 id) external view returns (address) {
        return _token().ownerOf[id];
    }

    function setNumTradesAllowedAfterTransmog(
        uint16 numTrades
    ) public ownerOnly {
        _constants().NUM_TRADES_ALLOWED_AFTER_TRANSMOG = numTrades;
    }

    function getNumTradesAllowedAfterTransmog() public view returns (uint16) {
        return _constants().NUM_TRADES_ALLOWED_AFTER_TRANSMOG;
    }

    function setEquipmentTradingIsEnabled(bool enabled) public ownerOnly {
        _token().equipmentTradingIsEnabled = enabled;
    }

    function getEquipmentTradingIsEnabled() public view returns (bool) {
        return _token().equipmentTradingIsEnabled;
    }

    function setEquipmentMintingIsEnabled(bool enabled) public ownerOnly {
        _token().equipmentMintingIsEnabled = enabled;
    }

    function getEquipmentMintingIsEnabled() public view returns (bool) {
        return _token().equipmentMintingIsEnabled;
    }

    function setChestTradingIsEnabled(bool enabled) public ownerOnly {
        _token().chestTradingIsEnabled = enabled;
    }

    function getChestTradingIsEnabled() public view returns (bool) {
        return _token().chestTradingIsEnabled;
    }

    function setChestMintingIsEnabled(bool enabled) public ownerOnly {
        _token().chestMintingIsEnabled = enabled;
    }

    function getChestMintingIsEnabled() public view returns (bool) {
        return _token().chestMintingIsEnabled;
    }

    function getContractOwner() public view returns (address) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.contractOwner;
    }

    function setContractOwner(address newOwner) public ownerOnly {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.contractOwner = newOwner;
    }
}


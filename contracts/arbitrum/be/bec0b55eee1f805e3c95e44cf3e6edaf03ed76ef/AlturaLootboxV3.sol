// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./UUPSUpgradeable.sol";
import "./ERC1155Upgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./IERC1155Receiver.sol";

/// @title Altura LootBox Manager V3
/// @author Altura - https://www.alturanft.com/
/// @notice Altura LootBox contract implementation
contract AlturaLootboxV3 is UUPSUpgradeable, ERC1155Upgradeable, AccessControlEnumerableUpgradeable {
    uint256 private nextBoxId;
    Box[] private boxes;

    struct Box {
        address creator;
        address paymentToken;
        uint256 price;
        uint128 supply;
        uint120 totalRarity;
        bool isLaunched;
        bool isPaused;
        Item[] items;
    }

    struct Item {
        address collectionAddress;
        uint256 tokenId;
        uint128 supply;
        uint120 rarity;
        bool isERC721;
    }

    event BoxCreated(uint256 boxId, address creator);
    event BoxLaunched(uint256 boxId, uint128 initialSupply, address paymentToken, uint256 price);
    event BoxSupplyIncreased(uint256 boxId, uint128 supplyIncrease);
    event BoxPriceChanged(uint256 boxId, address paymentToken, uint256 price);
    event BoxPaused(uint256 boxId, bool isPaused);
    event KeyPurchased(uint256 boxId, address buyer);
    event KeyUsed(uint256 boxId, uint256 itemId, address user, address collectionAddress, uint256 tokenId);
    event ItemAdded(
        uint256 boxId,
        address collectionAddress,
        uint256 tokenId,
        uint128 supply,
        uint120 rarity,
        bool isERC721
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory _uri) public initializer {
        __ERC1155_init(_uri);
        __AccessControlEnumerable_init();

        __AlturaLootbox_init_unchained();
    }

    function __AlturaLootbox_init_unchained() internal onlyInitializing {
        nextBoxId = 1;
        boxes.push();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function createBox() external {
        uint256 currentId = nextBoxId;

        Box storage newBox = boxes.push();
        newBox.creator = msg.sender;

        emit BoxCreated(currentId, msg.sender);
        unchecked {
            currentId++;
        }
        nextBoxId = currentId;
    }

    function launchBox(uint256 boxId, uint128 initialSupply, address paymentToken, uint256 price) external {
        Box storage targetBox = _getBoxInternal(boxId);
        require(targetBox.creator == msg.sender, "Only creator");
        require(!targetBox.isLaunched, "Box already launched");

        targetBox.supply = initialSupply;
        targetBox.paymentToken = paymentToken;
        targetBox.price = price;
        targetBox.isLaunched = true;

        emit BoxLaunched(boxId, initialSupply, paymentToken, price);
    }

    function increaseBoxSupply(uint256 boxId, uint128 supplyIncrease) external {
        Box storage targetBox = _getBoxInternal(boxId);
        require(targetBox.creator == msg.sender, "Only creator");
        require(targetBox.isLaunched, "Box isn't launched");

        targetBox.supply += supplyIncrease;
        emit BoxSupplyIncreased(boxId, supplyIncrease);
    }

    function changeBoxPrice(uint256 boxId, address paymentToken, uint256 price) external {
        Box storage targetBox = _getBoxInternal(boxId);
        require(targetBox.creator == msg.sender, "Only creator");
        require(targetBox.isLaunched, "Box isn't launched");

        targetBox.paymentToken = paymentToken;
        targetBox.price = price;

        emit BoxPriceChanged(boxId, paymentToken, price);
    }

    function setBoxPaused(uint256 boxId, bool isPaused) external {
        Box storage targetBox = _getBoxInternal(boxId);
        require(targetBox.creator == msg.sender, "Only creator");
        require(targetBox.isLaunched, "Box isn't launched");

        targetBox.isPaused = isPaused;
        emit BoxPaused(boxId, isPaused);
    }

    function addItem(
        uint256 boxId,
        address collectionAddress,
        uint256 tokenId,
        uint128 supply,
        uint120 rarity,
        bool isERC721
    ) external {
        Box storage targetBox = _getBoxInternal(boxId);
        require(targetBox.creator == msg.sender, "Only creator");
        require(rarity > 0 && rarity < 101, "Invalid item rarity");

        if (!isERC721) IERC1155(collectionAddress).safeTransferFrom(msg.sender, address(this), tokenId, supply, "0x0");
        else IERC721(collectionAddress).transferFrom(msg.sender, address(this), tokenId);

        targetBox.items.push(Item(collectionAddress, tokenId, !isERC721 ? supply : 1, rarity, isERC721));
        targetBox.totalRarity += rarity;

        emit ItemAdded(boxId, collectionAddress, tokenId, supply, rarity, isERC721);
    }

    function buyKey(uint256 boxId) external payable {
        Box memory targetBox = getBox(boxId);
        require(!targetBox.isPaused, "Box is paused");
        require(targetBox.supply > 0, "No keys available");

        if (targetBox.paymentToken == address(0x0)) {
            require(msg.value == targetBox.price, "Insufficient payment");

            (bool paymentSuccess, ) = targetBox.creator.call{value: targetBox.price}("");
            require(paymentSuccess, "Payment failed");
        } else {
            IERC20 targetPaymentToken = IERC20(targetBox.paymentToken);

            bool paymentSuccess = targetPaymentToken.transferFrom(msg.sender, targetBox.creator, targetBox.price);
            require(paymentSuccess, "Payment failed");
        }

        unchecked {
            boxes[boxId].supply -= 1;
        }

        _mint(msg.sender, boxId, 1, "0x0");
        emit KeyPurchased(boxId, msg.sender);
    }

    function useKey(uint256 boxId) external {
        Box memory targetBox = getBox(boxId);
        require(!targetBox.isPaused, "Box is paused");
        require(balanceOf(msg.sender, boxId) > 0, "You don't own a key");

        uint256 maxLength = targetBox.items.length;
        require(maxLength > 0 && targetBox.totalRarity > 0, "No items in box");

        address sender = msg.sender;
        uint256 pseudoRandom = block.prevrandao % targetBox.totalRarity;
        uint256 i = block.prevrandao % maxLength;
        uint256 j;
        while (j < maxLength) {
            Item memory item = targetBox.items[i];

            if (pseudoRandom < item.rarity && item.supply > 0) {
                uint128 newSupply = item.supply - 1;
                boxes[boxId].items[i].supply = newSupply;

                if (newSupply == 0) {
                    delete boxes[boxId].items[i];
                    boxes[boxId].totalRarity -= item.rarity;
                }
                _burn(sender, boxId, 1);

                if (!item.isERC721)
                    IERC1155(item.collectionAddress).safeTransferFrom(address(this), sender, item.tokenId, 1, "0x0");
                else IERC721(item.collectionAddress).transferFrom(address(this), sender, item.tokenId);

                emit KeyUsed(boxId, i, sender, item.collectionAddress, item.tokenId);
                return;
            }

            unchecked {
                pseudoRandom -= item.rarity;
                j++;
                i++;
                if (i == maxLength) i = 0;
            }
        }
        revert("Unable to use key");
    }

    function getBox(uint256 boxId) public view returns (Box memory) {
        return _getBoxInternal(boxId);
    }

    function _getBoxInternal(uint256 boxId) internal view returns (Box storage) {
        require(boxId > 0 && boxId < nextBoxId, "Invalid box id");
        return boxes[boxId];
    }

    function uri(uint256 itemId) public view override returns (string memory) {
        string memory _tokenURI = StringsUpgradeable.toString(itemId);
        string memory _baseURI = super.uri(itemId);

        return string(abi.encodePacked(_baseURI, _tokenURI));
    }

    function contractURI() public view returns (string memory) {
        return super.uri(0);
    }

    function name() public pure returns (string memory) {
        return "Altura LootBox Keys";
    }

    function symbol() public pure returns (string memory) {
        return "ALBK";
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155Upgradeable, AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    receive() external payable {
        revert();
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}


// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ERC1155Upgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./IGridFireEditions.sol";
import "./IGridFirePayment.sol";

contract GridFireEditions is
    IGridFireEditions,
    Initializable,
    ERC1155Upgradeable,
    ERC1155HolderUpgradeable,
    ERC1155SupplyUpgradeable,
    OwnableUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    mapping(uint256 => GridFireEdition) private editions;
    CountersUpgradeable.Counter private editionIdTracker;
    address payable gridFirePaymentAddress;

    function initialize(address _gridFirePaymentAddress) public initializer {
        assert(_gridFirePaymentAddress != address(0));
        __ERC1155_init("");
        __Ownable_init();
        gridFirePaymentAddress = payable(address(_gridFirePaymentAddress));
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function _transferEditionPayment(
        uint256 editionId,
        uint256 amountPaid,
        address artist,
        bytes32 releaseId
    ) private {
        IGridFirePayment gridFirePayment = IGridFirePayment(gridFirePaymentAddress);
        (uint256 artistShare, uint256 platformShare) = gridFirePayment.transferEditionPayment(
            msg.sender,
            artist,
            amountPaid
        );
        emit PurchaseEdition(msg.sender, artist, editionId, amountPaid, artistShare, platformShare, releaseId);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155SupplyUpgradeable, ERC1155Upgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function mintEdition(
        uint256 amount,
        uint256 price,
        string calldata metadataUri,
        bytes32 releaseId,
        bytes32 objectId
    ) external {
        require(amount > 0 && price > 0);
        require(bytes(metadataUri).length != 0);
        require(releaseId.length != 0 && objectId.length != 0);
        editionIdTracker.increment();
        uint256 editionId = editionIdTracker.current();
        _mint(address(this), editionId, amount, "");
        editions[editionId].price = price;
        editions[editionId].uri = metadataUri;
        emit EditionMinted(releaseId, msg.sender, objectId, editionId, amount, price);
    }

    function purchaseGridFireEdition(
        uint256 editionId,
        uint256 amountPaid,
        address paymentAddress,
        bytes32 releaseId
    ) external {
        require(balanceOf(address(this), editionId) != 0);
        require(amountPaid >= editions[editionId].price);
        require(paymentAddress != address(0));
        require(releaseId.length > 0);
        _transferEditionPayment(editionId, amountPaid, paymentAddress, releaseId);
        _safeTransferFrom(address(this), msg.sender, editionId, 1, "");
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155ReceiverUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function uri(uint256 editionId) public view override(ERC1155Upgradeable) returns (string memory) {
        return (editions[editionId].uri);
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}


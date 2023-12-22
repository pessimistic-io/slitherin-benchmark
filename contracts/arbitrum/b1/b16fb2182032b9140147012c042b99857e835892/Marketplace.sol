// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./IERC721Upgradeable.sol";
import "./AddressUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./ERC721Holder.sol";

import "./Initializable.sol";

import "./OwnableUpgradeable.sol";
import "./MarketplaceStorage.sol";

contract Marketplace is
    Initializable,
    MarketplaceStorage,
    ERC721Holder,
    OwnableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _orderIds;
    using AddressUpgradeable for address;

    function initialize(
        address _currencyAddress,
        address _owner,
        address _feeHolder,
        uint256 _feeRate
    ) public initializer {
        currencyAddress = _currencyAddress;
        feeHolder = _feeHolder;
        feeRate = _feeRate;
        __Ownable_init();
        transferOwnership(_owner);
    }

    function setFeeRate(uint256 _feeRate) public onlyOwner {
        require(
            _feeRate < 1000000,
            "Marketplace: The owner cut should be between 0 and 999,999"
        );

        feeRate = _feeRate;
        emit ChangedFeeRate(feeRate);
    }

    function setFeeHolder(address _feeHolder) public onlyOwner {
        require(
            _feeHolder != address(this) &&
                _feeHolder != address(0),
            "Marketplace: _feeHolder is invalid"
        );
        feeHolder = _feeHolder;
        emit ChangedFeeHolder(feeHolder);
    }

    /**
     * @dev Creates a new order
     * @param nftAddress - Token contract address
     * @param assetId - ID of the published token
     * @param price - Price in unit for the supported coin
     */

    function createOrder(
        address nftAddress,
        uint256 assetId,
        uint256 price
    ) external payable {
        require(
            nftAddress.isContract(),
            "Marketplace: The nftAddress should be a contract"
        );
        require(price > 0, "Marketplace: Price should be bigger than 0");

        _orderIds.increment();

        uint256 orderId = _orderIds.current();

        uint256 feeAmount = getFeeAmount(price);

        orders[orderId] = Order({
            id: orderId,
            seller: payable(msg.sender),
            nftAddress: nftAddress,
            assetId: assetId,
            price: price,
            fee: feeAmount
        });

        IERC721Upgradeable(nftAddress).safeTransferFrom(msg.sender, address(this), assetId);

        emit OrderCreated(
            orderId,
            assetId,
            msg.sender,
            nftAddress,
            price,
            feeAmount
        );
    }

    function updatePrice(
        uint256 orderId,
        uint256 newPrice
    ) external {
        require(msg.sender == orders[orderId].seller, "Marketplace: Unauthorized user");
        require(newPrice > 0, "Marketplace: Price should be bigger than 0");
        uint256 oldPrice = orders[orderId].price;
        uint256 feeAmount = getFeeAmount(newPrice);
        orders[orderId].price = newPrice;
        orders[orderId].fee = feeAmount;
        emit PriceUpdated(orderId, oldPrice, newPrice);
    }

    /**
     * @dev Cancel an already published order
     *  can only be canceled by seller
     * @param orderId - ID of the published token
     */
    function cancelOrder(uint256 orderId) public {
        address seller = msg.sender;
        Order memory order = orders[orderId];

        require(order.id != 0, "Marketplace: Asset not published");
        require(order.seller == seller, "Marketplace: Unauthorized user");

        uint256 assetId = order.assetId;
        address nftAddress = order.nftAddress;
        delete orders[orderId];

        IERC721Upgradeable(nftAddress).safeTransferFrom(address(this), seller, assetId);

        emit OrderCancelled(orderId, assetId, seller, nftAddress);
    }

    function getFeeAmount(uint256 amount) public view returns(uint) {
        uint feeAmount = 0;
        if (feeRate > 0) {
            // Calculate sale share
            feeAmount = (amount  * feeRate) / 1000000;
        }
        return feeAmount;
    }

    /**
     * @dev Executes the sale for a published token
     * @param orderId - ID order
     * @param price - price for each asset
     */
    function executeOrder(
        uint256 orderId,
        uint256 price
    ) public payable {
        address buyer = msg.sender;

        Order storage order = orders[orderId];

        require(order.id != 0, "Marketplace: Asset not published");

        require(order.price == price, "Marketplace: The price is not correct");

        address payable seller = order.seller;

        require(seller != address(0), "Marketplace: Invalid address");
        require(seller != buyer, "Marketplace: Unauthorized user");

        address nftAddress = order.nftAddress;
        uint256 assetId = order.assetId;
        uint256 feeAmount = order.fee;

        delete orders[orderId];

        if (feeAmount > 0) {
            IERC20Upgradeable(currencyAddress).safeTransferFrom(
                buyer,
                feeHolder,
                feeAmount
            );
        }

        IERC20Upgradeable(currencyAddress).safeTransferFrom(
            buyer,
            seller,
            price - feeAmount
        );

        IERC721Upgradeable(nftAddress).safeTransferFrom(address(this), buyer, assetId);

        emit OrderSuccessful(
            orderId,
            assetId,
            seller,
            nftAddress,
            price,
            buyer
        );
    }
}


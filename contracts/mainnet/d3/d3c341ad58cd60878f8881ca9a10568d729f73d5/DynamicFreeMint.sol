// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC721LazyMint.sol";
import "./PrimarySale.sol";
import "./CurrencyTransferLib.sol";

contract DynamicFreeMint is ERC721LazyMint, PrimarySale {
    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _saleRecipient,
        uint256 _pricePerToken,
        uint256 _mintForFree
    ) ERC721LazyMint(_name, _symbol, _royaltyRecipient, _royaltyBps) {
        _setupPrimarySaleRecipient(_saleRecipient);
        pricePerToken = _pricePerToken;
        mintForFree = _mintForFree;
    }

    mapping(address => uint256) public numClaimedForFree;
    uint256 public pricePerToken;
    uint256 public mintForFree;

    function _canLazyMint() internal view override returns (bool) {
        return msg.sender == owner();
    }

    function _transferTokensOnClaim(address _receiver, uint256 _quantity)
        internal
        virtual
        override
        returns (uint256 startTokenId)
    {
        startTokenId = super._transferTokensOnClaim(_receiver, _quantity);
        _collectPrice(_receiver, _quantity);
    }

    function _collectPrice(address _receiver, uint256 _quantity) private {
        uint256 freeAllowance = mintForFree - numClaimedForFree[_receiver];
        uint256 freeQuantity = _quantity > freeAllowance ? freeAllowance : _quantity;
        uint256 paidQuantity = _quantity > freeQuantity ? (_quantity - freeQuantity) : 0;

        uint256 totalPrice = paidQuantity * pricePerToken;
        if (paidQuantity > 0) {
            require(msg.value == totalPrice, "Incorrect payment amount");
        }

        CurrencyTransferLib.safeTransferNativeToken(primarySaleRecipient(), totalPrice);

        numClaimedForFree[_receiver] += freeQuantity;
    }

    function priceForAddress(address _address, uint256 _quantity)
        external
        view
        returns (uint256 price)
    {
        uint256 freeAllowance = mintForFree - numClaimedForFree[_address];
        uint256 freeQuantity = _quantity > freeAllowance ? freeAllowance : _quantity;
        uint256 paidQuantity = _quantity > freeQuantity ? (_quantity - freeQuantity) : 0;

        price = paidQuantity * pricePerToken;

        return price;
    }

    function _canSetPrimarySaleRecipient() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }

    function setPricePerToken(uint256 _newPrice) external {
        require(msg.sender == owner(), "Not authorized");
        pricePerToken = _newPrice;
    }
}

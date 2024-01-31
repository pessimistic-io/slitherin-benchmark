// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "./Initializable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {IMarketplaceFeeEngine} from "./IMarketplaceFeeEngine.sol";
import {MarketplaceFeeEngineStorage} from "./MarketplaceFeeEngineStorage.sol";

contract MarketplaceFeeEngine is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    IMarketplaceFeeEngine,
    MarketplaceFeeEngineStorage
{
    function initialize(address payable _feeRecipient, uint256 _platformFee)
        public
        initializer
    {
        __Ownable_init();
        feeReceipient = _feeRecipient;
        platformFee = _platformFee;
    }

    // For UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override {
        require(_msgSender() == owner(), "MPFEngine: caller is not owner");
    }

    function setFeeReceipient(address payable _feeRecipient)
        external
        override
        onlyOwner
    {
        feeReceipient = _feeRecipient;
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee < 5000, "MPFEngine: platformFee exceeds limit");
        platformFee = _platformFee;
    }

    function setMarketplaceFee(
        string calldata marketplace,
        address payable[] calldata recipients,
        uint256[] calldata fees
    ) external onlyOwner {
        require(recipients.length == fees.length, "MPFEngine: length mismatch");
        uint256 sum = 0;
        for (uint256 i = 0; i < fees.length; i++) {
            sum += fees[i];
        }
        require(sum < 5000, "MPEngine: platformFee exceeds limit");
        bytes32 id = keccak256(abi.encodePacked(marketplace));
        marketplaceRecipients[id] = recipients;
        marketplaceFees[id] = fees;
    }

    function setMarketplaceFeeByCurrency(
        string calldata marketplace,
        address currency,
        uint256[] calldata fees
    ) external onlyOwner {
        bytes32 id = keccak256(abi.encodePacked(marketplace));
        require(
            marketplaceRecipients[id].length == fees.length,
            "MPFEngine: length mismatch"
        );
        uint256 sum = 0;
        for (uint256 i = 0; i < fees.length; i++) {
            sum += fees[i];
        }
        require(sum < 5000, "MPEngine: platformFee exceeds limit");
        marketplaceFeesByCurrency[id][currency] = fees;
    }

    function addMarketplaceCollections(
        string calldata marketplace,
        address[] calldata collections
    ) external onlyOwner {
        bytes32 id = keccak256(abi.encodePacked(marketplace));
        for (uint256 i = 0; i < collections.length; i++) {
            validCollections[id][collections[i]] = true;
        }
    }

    function removeMarketplaceCollections(
        string calldata marketplace,
        address[] calldata collections
    ) public onlyOwner {
        bytes32 id = keccak256(abi.encodePacked(marketplace));
        for (uint256 i = 0; i < collections.length; i++) {
            validCollections[id][collections[i]] = false;
        }
    }

    function getMarketplaceFeeByName(
        string calldata marketplace,
        address collection,
        uint256 value
    ) public view returns (address payable[] memory, uint256[] memory) {
        bytes32 id = keccak256(abi.encodePacked(marketplace));
        return getMarketplaceFee(id, collection, value);
    }

    function getMarketplaceFee(
        bytes32 id,
        address collection,
        uint256 value
    )
        public
        view
        override
        returns (address payable[] memory, uint256[] memory)
    {
        return getMarketplaceFee(id, address(0x0), collection, value);
    }

    function getMarketplaceFee(
        bytes32 id,
        address currency,
        address collection,
        uint256 value
    )
        public
        view
        override
        returns (address payable[] memory, uint256[] memory)
    {
        if (
            validCollections[id][collection] && marketplaceFees[id].length > 0
        ) {
            if (
                marketplaceFeesByCurrency[id][currency].length ==
                marketplaceFees[id].length
            ) {
                return (
                    marketplaceRecipients[id],
                    _computeAmounts(
                        value,
                        marketplaceFeesByCurrency[id][currency]
                    )
                );
            }
            return (
                marketplaceRecipients[id],
                _computeAmounts(value, marketplaceFees[id])
            );
        }
        address payable[] memory recipients = new address payable[](1);
        recipients[0] = feeReceipient;
        uint256[] memory fees = new uint256[](1);
        fees[0] = platformFee;
        return (recipients, _computeAmounts(value, fees));
    }

    function _computeAmounts(uint256 value, uint256[] memory fees)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory amounts = new uint256[](fees.length);
        uint256 totalAmount;
        for (uint256 i = 0; i < fees.length; i++) {
            amounts[i] = (value * fees[i]) / 10000;
            totalAmount = totalAmount + amounts[i];
        }
        require(totalAmount < value, "MPFEngine: invalid fee amount");
        return amounts;
    }
}


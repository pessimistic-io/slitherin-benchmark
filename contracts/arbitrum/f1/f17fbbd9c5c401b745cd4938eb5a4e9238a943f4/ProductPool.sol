// SPDX-License-Identifier: GPL-3.0

/// This contract is responsible for recording product information.
pragma solidity ^0.8.0;

import {Initializable} from "./Initializable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import "./DataTypes.sol";
import {ConfigurationParam} from "./ConfigurationParam.sol";

contract ProductPool is Initializable, ReentrancyGuard {
    address public adminAddress;
    address public ownerAddress;
    mapping(uint256 => DataTypes.ProductInfo) productPool;
    uint256[] productIdList;

    /// @dev Initialise important addresses for the contract.
    function initialize(address _adminAddress) external initializer {
        _initNonReentrant();
        adminAddress = _adminAddress;
        ownerAddress = msg.sender;
    }

    /**
     * notice Launch new products.
     * @param product Product info.
     */
    function _s_publishProduct(DataTypes.ProductInfo memory product) external onlyOwner returns (bool) {
        require(product.cryptoType != address(0), "BasePositionManager: the cryptoType is null address");
        require(
            product.cryptoType == ConfigurationParam.WETH || product.cryptoType == ConfigurationParam.WBTC,
            "BasePositionManager: the cryptoType is error address"
        );
        if (product.cryptoType == ConfigurationParam.WETH) {
            product.cryptoExchangeAddress = ConfigurationParam.WETHCHAIN;
        } else {
            product.cryptoExchangeAddress = ConfigurationParam.WBTCCHAIN;
        }
        productPool[product.productId] = product;
        productIdList.push(product.productId);
        emit AddProduct(msg.sender, product);
        return true;
    }

    /**
     * notice Update product solds.
     * @param productId Product id.
     * @param sellAmount Sell amount.
     */
    function updateSoldTotalAmount(uint256 productId, uint256 sellAmount) external onlyAdmin returns (bool) {
        productPool[productId].soldTotalAmount = productPool[productId].soldTotalAmount + sellAmount;
        return true;
    }

    /**
     * notice Renew the amount available for sale.
     * @param productId Product id.
     * @param amount Sale amount.
     * @param boo Increase or decrease.
     */
    function setSaleTotalAmount(uint256 productId, uint256 amount, bool boo) external onlyOwner returns (bool) {
        if (boo) {
            productPool[productId].saleTotalAmount = productPool[productId].saleTotalAmount + amount;
        } else {
            uint256 TotalAmount = productPool[productId].saleTotalAmount - amount;
            require(
                TotalAmount >= productPool[productId].soldTotalAmount,
                "ProductManager: cannot be less than the pre-sale limit"
            );
            productPool[productId].saleTotalAmount = TotalAmount;
        }
        return true;
    }

    /**
     * notice Update product delivery status.
     * @param productId Product id.
     * @param resultByCondition ResultByCondition state.
     */
    function _s_retireProductAndUpdateInfo(
        uint256 productId,
        DataTypes.ProgressStatus resultByCondition
    ) external onlyAdmin returns (bool) {
        productPool[productId].resultByCondition = resultByCondition;
        return true;
    }

    function getProductInfoByPid(uint256 productId) external view returns (DataTypes.ProductInfo memory) {
        return productPool[productId];
    }

    function getProductList() public view returns (DataTypes.ProductInfo[] memory) {
        uint256 count;
        for (uint256 i = 0; i < productIdList.length; i++) {
            if (productPool[productIdList[i]].resultByCondition == DataTypes.ProgressStatus.UNDELIVERED) {
                count++;
            }
        }
        DataTypes.ProductInfo[] memory ProductList = new DataTypes.ProductInfo[](count);
        uint256 j;
        for (uint256 i = 0; i < productIdList.length; i++) {
            if (productPool[productIdList[i]].resultByCondition == DataTypes.ProgressStatus.UNDELIVERED) {
                ProductList[j] = productPool[productIdList[i]];
                j++;
            }
        }
        return ProductList;
    }

    function getAllProductList() public view returns (DataTypes.ProductInfo[] memory) {
        DataTypes.ProductInfo[] memory ProductList = new DataTypes.ProductInfo[](productIdList.length);
        for (uint256 i = 0; i < productIdList.length; i++) {
            ProductList[i] = productPool[productIdList[i]];
        }
        return ProductList;
    }

    modifier onlyOwner() {
        require(ownerAddress == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    modifier onlyAdmin() {
        require(adminAddress == msg.sender, "Ownable: caller is not the admin");
        _;
    }

    event AddProduct(address indexed owner, DataTypes.ProductInfo indexed productId);
}


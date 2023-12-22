// SPDX-License-Identifier: UNLICENSED

/// This contract is responsible for LP investment record management.

pragma solidity ^0.8.9;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./DataTypes.sol";

contract LPPool is Ownable, ReentrancyGuard {
    address public proxy;
    mapping(address => DataTypes.LPAmountInfo[]) LPAmountPool;
    DataTypes.LPPendingInit[] LPPendingInitList;
    DataTypes.HedgingAggregatorInfo[] productHedgingAggregatorPool;

    constructor(address _proxy) {
        proxy = _proxy;
    }

    /**
     * notice Update the agency contract address.
     * @param _proxy Contract address.
     */
    function updateProxy(address _proxy) public onlyOwner {
        proxy = _proxy;
    }

    /**
     * notice Make an appointment to withdraw money and record the appointment time.
     * @param lPAddress Contract address.
     * @param purchaseHeightInfo Deposit height record.
     */
    function reservationWithdrawal(address lPAddress, uint256 purchaseHeightInfo) external onlyProxy returns (bool) {
        DataTypes.LPAmountInfo[] storage lPAddressInfo = LPAmountPool[lPAddress];
        require(lPAddressInfo.length > 0, "LPPoolManager: data does not exist");
        for (uint256 i = 0; i < lPAddressInfo.length; i++) {
            if (purchaseHeightInfo == lPAddressInfo[i].purchaseHeightInfo) {
                lPAddressInfo[i].reservationTime = block.timestamp;
            }
        }
        return true;
    }

    /// @dev New LP investment record.
    function addLPAmountInfo(uint256 _amount, address _lPAddress) external onlyProxy returns (bool) {
        LPPendingInitList.push(
            DataTypes.LPPendingInit({
                amount: _amount,
                lPAddress: _lPAddress,
                createTime: block.timestamp,
                purchaseHeightInfo: block.number
            })
        );
        return true;
    }

    /// @dev LP investment net contract update.
    function dealLPPendingInit(uint256 coefficient) external onlyProxy returns (bool) {
        if (LPPendingInitList.length == 0) {
            return true;
        }
        for (uint256 i = 0; i < LPPendingInitList.length; i++) {
            DataTypes.LPAmountInfo memory lPAmountInfo = DataTypes.LPAmountInfo({
                amount: LPPendingInitList[i].amount,
                initValue: coefficient,
                lPAddress: LPPendingInitList[i].lPAddress,
                createTime: LPPendingInitList[i].createTime,
                reservationTime: 0,
                purchaseHeightInfo: LPPendingInitList[i].purchaseHeightInfo
            });
            LPAmountPool[LPPendingInitList[i].lPAddress].push(lPAmountInfo);
        }
        delete (LPPendingInitList);
        return true;
    }

    /// @dev LP withdrawal processing.
    function deleteLPAmountInfoByParam(
        address lPAddress,
        uint256 purchaseHeightInfo
    ) external onlyProxy returns (bool) {
        DataTypes.LPAmountInfo[] storage lPAddressInfo = LPAmountPool[lPAddress];
        for (uint256 i = 0; i < lPAddressInfo.length; i++) {
            if (purchaseHeightInfo == lPAddressInfo[i].purchaseHeightInfo) {
                lPAddressInfo[i] = lPAddressInfo[lPAddressInfo.length - 1];
                lPAddressInfo.pop();
            }
        }
        return true;
    }

    /// @dev LP investment base update.
    function updateInitValue(address lPAddress, uint256 purchaseHeightInfo, uint256 _initValue) private returns (bool) {
        DataTypes.LPAmountInfo[] storage lPAddressInfo = LPAmountPool[lPAddress];
        for (uint256 i = 0; i < lPAddressInfo.length; i++) {
            if (purchaseHeightInfo == lPAddressInfo[i].purchaseHeightInfo) {
                lPAddressInfo[i].initValue = _initValue;
            }
        }
        return true;
    }

    /// @dev Hedging pool adds hedging data.
    function addHedgingAggregator(
        DataTypes.HedgingAggregatorInfo memory hedgingAggregator
    ) external onlyProxy returns (bool) {
        productHedgingAggregatorPool.push(hedgingAggregator);
        return true;
    }

    /// @dev Processing hedge pool
    function deleteHedgingAggregator(uint256 _releaseHeight) external onlyProxy returns (bool) {
        uint256 hedgingLocation;
        uint256 poolLength = productHedgingAggregatorPool.length;
        require(productHedgingAggregatorPool.length > 0, "CustomerManager: productHedgingAggregatorPool is null");
        for (uint256 i = 0; i < productHedgingAggregatorPool.length; i++) {
            if (productHedgingAggregatorPool[i].releaseHeight > _releaseHeight) {
                hedgingLocation = i;
                break;
            }
        }
        if (hedgingLocation == 0) {
            delete productHedgingAggregatorPool;
        } else {
            uint256 lastHedgingLocation = hedgingLocation;
            for (uint256 i = 0; i < poolLength - hedgingLocation; i++) {
                productHedgingAggregatorPool[i] = productHedgingAggregatorPool[lastHedgingLocation];
                lastHedgingLocation++;
            }
            for (uint256 i = 0; i <= hedgingLocation - 1; i++) {
                productHedgingAggregatorPool.pop();
            }
        }
        return true;
    }

    function getProductHedgingAggregatorPool() external view returns (DataTypes.HedgingAggregatorInfo[] memory) {
        return productHedgingAggregatorPool;
    }

    function getLPPendingInit() external view returns (DataTypes.LPPendingInit[] memory) {
        return LPPendingInitList;
    }

    function getLPAmountInfo(address lPAddress) external view returns (DataTypes.LPAmountInfo[] memory) {
        return LPAmountPool[lPAddress];
    }

    function getLPAmountInfoByParams(
        address lPAddress,
        uint256 purchaseHeightInfo
    ) external view returns (DataTypes.LPAmountInfo memory) {
        DataTypes.LPAmountInfo[] storage lPAddressInfo = LPAmountPool[lPAddress];
        DataTypes.LPAmountInfo memory result;
        for (uint256 i = 0; i < lPAddressInfo.length; i++) {
            if (purchaseHeightInfo == lPAddressInfo[i].purchaseHeightInfo) {
                result = lPAddressInfo[i];
            }
        }
        return result;
    }

    modifier onlyProxy() {
        require(proxy == msg.sender, "Ownable: caller is not the proxy");
        _;
    }
}


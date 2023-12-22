pragma solidity ^0.8.0;

import "./IFundingManager.sol";
import "./FundingManager.sol";

contract FundingManagerReader {

    address public fundingManager;

    constructor(address _fundingManager) public {
        fundingManager = _fundingManager;
    }

    function getFundingData(
        uint256 productId
    ) external view returns(
        int256 fundingPayment,
        int256 fundingRate,
        uint256 lastUpdateTimestamp
    ) {
        fundingPayment = IFundingManager(fundingManager).getFunding(productId);
        fundingRate = IFundingManager(fundingManager).getFundingRate(productId);
        lastUpdateTimestamp = FundingManager(fundingManager).lastUpdateTimes(productId);
    }
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Market.sol";

contract MarketCreator {
    function createMarket(
        address _collateralToken,
        address _conditionalToken,
        bytes32 _conditionId,
        uint _positionIdOutcome0,
        uint _positionIdOutcome1,
        uint _minAmount,
        uint _fee,
        address _feeRecipient
    ) external returns (address) {
        Market market = new Market(
            _collateralToken,
            _conditionalToken,
            _conditionId,
            _positionIdOutcome0,
            _positionIdOutcome1,
            _minAmount,
            _fee,
            _feeRecipient
        );
        market.transferOwnership(msg.sender);
        return (address(market));
    }
}

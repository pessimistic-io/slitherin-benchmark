// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./IDerivativeLogic.sol";

import "./ThirdPartyExecutionSyntheticId.sol";

/**
    Error codes:
    - S1 = CAN_NOT_BE_ZERO_ADDRESS
 */
contract OptionPutSyntheticId is IDerivativeLogic, ThirdPartyExecutionSyntheticId, Ownable {
    address private author;
    uint256 private commission;

    uint256 public constant BASE = 1e18;

    constructor(address _author, uint256 _commission) {
        /*
        {
            "author": "Opium.Team",
            "type": "option",
            "subtype": "put",
            "description": "Option Put logic contract"
        }
        */
        emit LogMetadataSet("{\"author\":\"Opium.Team\",\"type\":\"option\",\"subtype\":\"put\",\"description\":\"Option Put logic contract\"}");

        author = _author;
        commission = _commission;

        // Transfer contract's ownership to author on deployment
        transferOwnership(_author);
    }

    // margin - reference value for option nominal
    // params[0] - strikePrice - denominated in E18
    // params[1] - collateralization
    // params[2] - fixedPremium - (optional)
    function validateInput(LibDerivative.Derivative calldata _derivative) external override pure returns (bool) {
        return (
            // Derivative
            _derivative.margin > 0 && // nominal > 0
            _derivative.params.length == 3 &&

            _derivative.params[0] > 0 && // Strike price > 0
            _derivative.params[1] <= BASE && _derivative.params[1] > 0 // 100% >= Collateralization > 0
        );
    }

    function getSyntheticIdName() external override pure returns (string memory) {
        return "OPT-P";
    }

    function getMargin(LibDerivative.Derivative calldata _derivative) external override pure returns (uint256 buyerMargin, uint256 sellerMargin) {
        uint256 collateralization = _derivative.params[1];
        uint256 fixedPremium = _derivative.params[2];
        buyerMargin = fixedPremium;

        uint256 nominal = _derivative.margin;
        sellerMargin = nominal * collateralization / BASE;
    }

    function getExecutionPayout(LibDerivative.Derivative calldata _derivative, uint256 _result) external override pure returns (uint256 buyerPayout, uint256 sellerPayout) {
        uint256 strikePrice = _derivative.params[0];
        uint256 collateralization = _derivative.params[1];
        uint256 fixedPremium = _derivative.params[2];
        uint256 nominal = _derivative.margin;
        uint256 sellerMargin = nominal * collateralization / BASE;

        // If result price is less than strike price, buyer is being paid out
        if (_result < strikePrice) {
            // Buyer payout is calculated as nominal multiplied by underlying result price depreciation from strike price
            buyerPayout = nominal * (strikePrice - _result) / strikePrice;

            // If Buyer payout exceeds the initial seller margin, then it's being capped (limited) by it
            if (buyerPayout > sellerMargin) {
                buyerPayout = sellerMargin;
            }

            // Seller payout is calculated as a reminder from seller margin and buyer payout
            sellerPayout = sellerMargin - buyerPayout;
        } else {
            // If result price is lower or equal to strike price, buyer is not being paid out
            buyerPayout = 0;
            
            // Seller receives its margin back as a payout
            sellerPayout = sellerMargin;
        }

        // Seller payout is always increased by fixed premium if specified
        sellerPayout = sellerPayout + fixedPremium;
    }

    /** COMMISSION */
    /// @notice Getter for syntheticId author address
    /// @return address syntheticId author address
    function getAuthorAddress() external override view returns (address) {
        return author;
    }

    /// @notice Getter for syntheticId author commission
    /// @return uint256 syntheticId author commission
    function getAuthorCommission() external override view returns (uint256) {
        return commission;
    }

    /** THIRDPARTY EXECUTION */
    function thirdpartyExecutionAllowed(address _derivativeOwner) external override view returns (bool) {
        return isThirdPartyExecutionAllowed[_derivativeOwner];
    }

    function allowThirdpartyExecution(bool _allow) external override {
        _allowThirdpartyExecution(msg.sender, _allow);
    }

    /** GOVERNANCE */
    function setAuthorAddress(address _author) external onlyOwner {
        require(_author != address(0), "S1");
        author = _author;
    }

    function setAuthorCommission(uint256 _commission) external onlyOwner {
        commission = _commission;
    }
}


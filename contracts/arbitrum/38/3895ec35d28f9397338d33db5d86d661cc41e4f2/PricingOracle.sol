// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./AccessControl.sol";
import "./PRBMathSD59x18.sol";
import "./PRBMathUD60x18.sol";
import "./IPricingOracle.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title PricingOracle for keeping all of the essential loan data and generate loan health
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract PricingOracle is IPricingOracle, AccessControl {
    using PRBMathSD59x18 for int256;
    using PRBMathUD60x18 for uint256;

    uint256 public currentAverage;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    event AverageFloorPriceUpdated(
        address indexed _operator,
        uint256 _blocktime,
        uint256 _previousAverage,
        uint256 _currentAverage
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice update the current average
     */
    function updateAveragePrice(uint256 _newAverage) public onlyAdmin {
        emit AverageFloorPriceUpdated(
            msg.sender,
            block.timestamp,
            currentAverage,
            _newAverage
        );

        currentAverage = _newAverage;
    }

    /**
     * @notice return the current average
     */
    function getAssetAveragePrice() public view returns (uint256) {
        return currentAverage;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "PricingOracle: caller not admin"
        );
        _;
    }
}


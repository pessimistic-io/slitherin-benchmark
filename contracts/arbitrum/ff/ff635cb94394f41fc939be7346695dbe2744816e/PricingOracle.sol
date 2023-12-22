// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./AccessControl.sol";
import "./PRBMathSD59x18.sol";
import "./PRBMathUD60x18.sol";
import "./AggregatorV2V3Interface.sol";
import "./ITreasureNFTPriceTracker.sol";
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
    address public nftAddress;
    address public chainlinkPriceOracle;
    address public treasureNFTPriceTracker;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    event AverageFloorPriceUpdated(
        address indexed _operator,
        uint256 _blocktime,
        uint256 _previousAverage,
        uint256 _currentAverage
    );

    event ChangedChainlinkPriceOracle(
        address _previousPricingOracle,
        address _currentPricingOracle
    );

    event ChangedTreasureNFTPriceTracker(
        address _previousTreasureNFTPriceTracker,
        address _currentTreasureNFTPriceTracker
    );

    constructor(
        address _nftAddress,
        address _chainlinkPriceOracle,
        address _treasureNFTPriceTracker
    ) {
        nftAddress = _nftAddress;
        chainlinkPriceOracle = _chainlinkPriceOracle;
        treasureNFTPriceTracker = _treasureNFTPriceTracker;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice update the chainlinkPriceOracle address
     */
    function setChainlinkPriceOracle(
        address _chainlinkPriceOracle
    ) public onlyAdmin {
        emit ChangedChainlinkPriceOracle(
            chainlinkPriceOracle,
            _chainlinkPriceOracle
        );
        chainlinkPriceOracle = _chainlinkPriceOracle;
    }

    /**
     * @notice update the treasureNFTPriceTracker address
     */
    function setTreasureNFTPriceTracker(
        address _treasureNFTPriceTracker
    ) public onlyAdmin {
        emit ChangedTreasureNFTPriceTracker(
            treasureNFTPriceTracker,
            _treasureNFTPriceTracker
        );
        treasureNFTPriceTracker = _treasureNFTPriceTracker;
    }

    /**
     * @notice update the current average
     */
    function updateAveragePrice() public onlyAdmin {
        // normalize 8 digit oracle response to 18 digits
        // multiply average price in $MAGIC by the $MAGIC price
        // persist in USDC
        uint256 oldAverage = currentAverage;
        currentAverage = (uint256(
            AggregatorV2V3Interface(chainlinkPriceOracle).latestAnswer()
        ) *
            10 **
                (18 - AggregatorV2V3Interface(chainlinkPriceOracle).decimals()))
            .mul(
                ITreasureNFTPriceTracker(treasureNFTPriceTracker)
                    .getAveragePriceForCollection(
                        nftAddress,
                        FloorType.SUBFLOOR1
                    )
            );

        emit AverageFloorPriceUpdated(
            msg.sender,
            block.timestamp,
            oldAverage,
            currentAverage
        );
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


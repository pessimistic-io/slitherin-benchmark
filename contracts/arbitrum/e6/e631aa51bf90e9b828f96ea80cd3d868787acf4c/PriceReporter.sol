// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.6;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {IOrderManager} from "./IOrderManager.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {TokenConfig, IPriceFeed} from "./IPriceFeed.sol";

/**
 * @title PriceReporter
 * @notice Utility contract to call post prices and execute orders on a single transaction. Used on
 * testnet only
 */
contract PriceReporter is OwnableUpgradeable {
    IPriceFeed private oracle;
    IOrderManager private orderManager;
    mapping(address => bool) public isReporter;
    address[] public reporters;

    function initialize(address _oracle, address _orderManager) external initializer {
        __Ownable_init_unchained();
        require(_oracle != address(0), "PriceReporter:invalidOracle");
        require(_orderManager != address(0), "PriceReporter:invalidPositionManager");
        oracle = IPriceFeed(_oracle);
        orderManager = IOrderManager(_orderManager);
    }

    function postPriceAndExecuteOrders(address[] calldata tokens, uint256[] calldata prices, uint256[] calldata orders)
        external
    {
        require(isReporter[msg.sender], "PriceReporter:unauthorized");
        oracle.postPrices(tokens, prices);

        for (uint256 i = 0; i < orders.length;) {
            try orderManager.executeOrder(orders[i], payable(msg.sender)) {} catch {}
            unchecked {
                ++i;
            }
        }
    }

    function postPriceAndExecuteOrders(address[] calldata tokens, uint256[] calldata orders, bool enableTry)
        external
    {
        require(isReporter[msg.sender], "PriceReporter:unauthorized");

        uint256[] memory prices = new uint256[](tokens.length);
        for (uint i = 0; i < prices.length; ) {
            TokenConfig memory tc = oracle.tokenConfig(tokens[i]);
            ( , int256 price, , , ) = tc.chainlinkPriceFeed.latestRoundData();
            prices[i] = uint256(price);
            unchecked {
                ++i;
            }
        }
        oracle.postPrices(tokens, prices);

        for (uint256 i = 0; i < orders.length;) {
            if (enableTry) {
                try orderManager.executeOrder(orders[i], payable(msg.sender)) {} catch {}
            } else {
                orderManager.executeOrder(orders[i], payable(msg.sender));
            }
            unchecked {
                ++i;
            }
        }
    }

    function executeSwapOrders(uint256[] calldata orders) external {
        require(isReporter[msg.sender], "PriceReporter:unauthorized");
        if (orders.length > 0) {
            for (uint256 i = 0; i < orders.length; i++) {
                try orderManager.executeSwapOrder(orders[i], payable(msg.sender)) {} catch {}
            }
        }
    }

    function addReporter(address reporter) external onlyOwner {
        require(reporter != address(0), "PriceReporter:invalidAddress");
        require(!isReporter[reporter], "PriceReporter:reporterAlreadyAdded");
        isReporter[reporter] = true;
        reporters.push(reporter);
    }

    function removeReporter(address reporter) external onlyOwner {
        require(isReporter[reporter], "PriceReporter:reporterNotExists");
        isReporter[reporter] = false;
        for (uint256 i = 0; i < reporters.length; i++) {
            if (reporters[i] == reporter) {
                reporters[i] = reporters[reporters.length - 1];
                break;
            }
        }
        reporters.pop();
    }
}


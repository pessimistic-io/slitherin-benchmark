// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {IOrderManager} from "./IOrderManager.sol";

interface IPriceFeed {
    function postPrices(address[] calldata tokens, uint256[] calldata prices) external;
}

/**
 * @title PriceReporter
 * @notice Utility contract to call post prices and execute orders on a single transaction. Used on
 * testnet only
 */
contract PriceReporter is Ownable {
    uint256 public constant MAX_MARKET_ORDER_EXECUTION = 1000;
    IPriceFeed public immutable oracle;
    IOrderManager public immutable orderManager;
    mapping(address => bool) public isReporter;
    address[] public reporters;

    constructor(address _oracle, address _orderManager) {
        require(_oracle != address(0), "PriceReporter:invalidOracle");
        require(_orderManager != address(0), "PriceReporter:invalidPositionManager");
        oracle = IPriceFeed(_oracle);
        orderManager = IOrderManager(_orderManager);
    }

    function postPriceAndExecuteOrders(
        address[] calldata tokens,
        uint256[] calldata prices,
        uint256[] calldata leverageOrders,
        uint256[] calldata swapOrders
    ) external {
        require(isReporter[msg.sender], "PriceReporter:unauthorized");
        oracle.postPrices(tokens, prices);

        orderManager.executeMarketLeverageOrders(MAX_MARKET_ORDER_EXECUTION, payable(msg.sender));

        for (uint256 i = 0; i < leverageOrders.length;) {
            try orderManager.executeLeverageOrder(leverageOrders[i], payable(msg.sender)) {} catch {}
            unchecked {
                ++i;
            }
        }
        for (uint256 i = 0; i < swapOrders.length; i++) {
            try orderManager.executeSwapOrder(swapOrders[i], payable(msg.sender)) {} catch {}
            unchecked {
                ++i;
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


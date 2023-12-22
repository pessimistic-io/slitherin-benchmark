// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {IOrderManager} from "./IOrderManager.sol";

interface IPriceFeed {
    function postPrices(address[] calldata tokens, uint256[] calldata prices, uint256[] calldata timestamps) external;
}

/**
 * @title PriceReporter
 * @notice Utility contract to call post prices and execute orders on a single transaction
 */
contract PriceReporter is Ownable {
    IPriceFeed public immutable oracle;
    IOrderManager public immutable orderManager;
    mapping(address => bool) public isReporter;
    address[] public reporters;

    constructor(address _oracle, address _orderManager) {
        if (_oracle == address(0)) revert InvalidAddress();
        if (_orderManager == address(0)) revert InvalidAddress();

        oracle = IPriceFeed(_oracle);
        orderManager = IOrderManager(_orderManager);
    }

    function postPriceAndExecuteOrders(
        address[] calldata tokens,
        uint256[] calldata prices,
        uint256[] calldata priceTimestamps,
        uint256[] calldata leverageOrders,
        uint256[] calldata swapOrders
    ) external {
        if (!isReporter[msg.sender]) revert Unauthorized();

        oracle.postPrices(tokens, prices, priceTimestamps);

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
        if (reporter == address(0)) revert InvalidAddress();
        if (isReporter[reporter]) revert ReporterAlreadyAdded();

        isReporter[reporter] = true;
        reporters.push(reporter);
    }

    function removeReporter(address reporter) external onlyOwner {
        if (!isReporter[reporter]) revert ReporterNotExists();

        isReporter[reporter] = false;
        for (uint256 i = 0; i < reporters.length; i++) {
            if (reporters[i] == reporter) {
                reporters[i] = reporters[reporters.length - 1];
                break;
            }
        }
        reporters.pop();
    }

    error Unauthorized();
    error InvalidAddress();
    error ReporterAlreadyAdded();
    error ReporterNotExists();
}


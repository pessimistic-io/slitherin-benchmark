// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ICoreConfiguration.sol";
import "./IOracleConnector.sol";
import "./IOptionsFlashCallback.sol";

interface ICore {
    enum PositionStatus {
        PENDING,
        EXECUTED,
        CANCELED
    }

    enum OrderDirectionType {
        UP,
        DOWN
    }

    struct Counters {
        uint256 ordersCount;
        uint256 positionsCount;
        uint256 totalStableAmount;
    }

    struct Order {
        OrderDescription data;
        address creator;
        uint256 amount;
        uint256 reserved;
        uint256 available;
        bool closed;
    }

    struct OrderDescription {
        address oracle;
        uint256 percent;
        OrderDirectionType direction;
        uint256 rate;
        uint256 duration;
        bool reinvest;
    }

    struct Position {
        uint256 startTime;
        uint256 endTime;
        uint256 startPrice;
        uint256 endPrice;
        uint256 deviationPrice;
        uint256 protocolFee;
        uint256 amountCreator;
        uint256 amountAccepter;
        address winner;
        bool isCreatorWinner;
        PositionStatus status;
    }

    struct Accept {
        uint256 orderId;
        uint256 amount;
        bytes[] updateData;
    }

    function configuration() external view returns (ICoreConfiguration);

    function positionIdToOrderId(uint256) external view returns (uint256);

    function creatorToOrders(address, uint256) external view returns (uint256);

    function orderIdToPositions(uint256, uint256) external view returns (uint256);

    function counters() external view returns (Counters memory);

    function creatorOrdersCount(address creator) external view returns (uint256);

    function orderIdPositionsCount(uint256 orderId) external view returns (uint256);

    function positions(uint256 id) external view returns (Position memory);

    function orders(uint256 id) external view returns (Order memory);

    function availableFeeAmount() external view returns (uint256);

    function permitPeriphery() external view returns (address);

    event Accepted(uint256 indexed orderId, uint256 indexed positionId, Order order, Position position, uint256 amount);
    event AutoResolved(
        uint256 indexed orderId,
        uint256 indexed positionId,
        address indexed winner,
        uint256 protocolStableFee,
        uint256 autoResolveFee,
        uint256 referralID,
        ICoreUtilities.AffiliationUserData affiliation
    );
    event OrderCreated(uint256 orderId, Order order);
    event OrderClosed(uint256 orderId, Order order);
    event Flashloan(address indexed caller, address indexed receiver, uint256 amount, uint256 fee);
    event FeeClaimed(uint256 amount);
    event OrderIncreased(uint256 indexed orderId, uint256 amount);
    event OrderWithdrawal(uint256 indexed orderId, uint256 amount);

    function accept(address accepter, Accept[] memory data) external returns (uint256[] memory positionIds);

    function autoResolve(uint256 positionId, bytes[] calldata updateData) external returns (bool);

    function closeOrder(uint256 orderId) external returns (bool);

    function createOrder(
        address creator,
        OrderDescription memory data,
        uint256 amount
    ) external returns (uint256 orderId);

    function flashloan(address recipient, uint256 amount, bytes calldata data) external returns (bool);

    function increaseOrder(uint256 orderId, uint256 amount) external returns (bool);

    function withdrawOrder(uint256 orderId, uint256 amount) external returns (bool);
}


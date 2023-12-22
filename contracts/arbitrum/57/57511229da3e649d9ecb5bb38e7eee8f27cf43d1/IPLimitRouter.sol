// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./PYIndex.sol";

interface IPOrderMixinType {
    enum OrderType {
        SY_FOR_PT,
        PT_FOR_SY,
        SY_FOR_YT,
        YT_FOR_SY
    }

    // Fixed-size order part with core information
    struct StaticOrder {
        uint256 salt;
        uint256 expiry;
        uint256 nonce;
        OrderType orderType;
        address token;
        address YT;
        address maker;
        address receiver;
        uint256 makingAmount;
        uint256 lnImpliedRate;
        uint256 failSafeRate;
    }

    struct NormalResults {
        uint256 totalMaking;
        uint256 totalTaking;
        uint256 totalFee;
        uint256 totalNotionalVolume;
        uint256[] netMakings;
        uint256[] netTakings;
        uint256[] netFees;
        uint256[] notionalVolumes;
    }
}

struct Order {
    uint256 salt;
    uint256 expiry;
    uint256 nonce;
    IPOrderMixinType.OrderType orderType;
    address token;
    address YT;
    address maker;
    address receiver;
    uint256 makingAmount;
    uint256 lnImpliedRate;
    uint256 failSafeRate;
    bytes permit;
}

struct FillOrderParams {
    Order order;
    bytes signature;
    uint256 makingAmount;
}

interface IPLimitRouterCallback is IPOrderMixinType {
    function normalFillCallback(uint256 actualMaking, uint256 actualTaking, uint256 totalFee, bytes memory data)
        external
        returns (bytes memory);
}

interface IPLimitRouter is IPOrderMixinType {
    struct OrderStatus {
        uint128 filledAmount;
        uint128 remaining;
    }

    event OrderCanceled(address indexed maker, bytes32 indexed orderHash);

    event OrderFilled(
        bytes32 indexed orderHash,
        OrderType indexed orderType,
        address indexed YT,
        address token,
        uint256 netInputFromMaker,
        uint256 netOutputToMaker,
        uint256 feeAmount,
        uint256 notionalVolume
    );

    // @dev actualMaking, actualTaking are in the SY form
    function normalFill(FillOrderParams[] memory params, address receiver, uint256 maxTaking, bytes calldata callback)
        external
        returns (uint256 actualMaking, uint256 actualTaking, uint256 totalFee, bytes memory callbackReturn);

    function feeRecipient() external view returns (address);

    function hashOrder(Order memory order) external view returns (bytes32);

    function cancelSingle(Order calldata order) external;

    function cancelBatch(Order[] calldata orders) external;

    function orderStatusesRaw(bytes32[] memory orderHashes)
        external
        view
        returns (uint256[] memory remainingsRaw, uint256[] memory filledAmounts);

    function orderStatuses(bytes32[] memory orderHashes)
        external
        view
        returns (uint256[] memory remainings, uint256[] memory filledAmounts);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function simulate(address target, bytes calldata data) external payable;
}


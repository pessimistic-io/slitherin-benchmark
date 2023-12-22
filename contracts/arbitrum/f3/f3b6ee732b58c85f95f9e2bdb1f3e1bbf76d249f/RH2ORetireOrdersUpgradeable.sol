// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./EIP712Upgradeable.sol";
import "./ECDSA.sol";

import "./IMintersRegistry.sol";
import "./IRetiredWaterCredit.sol";

import "./console.sol";

contract RH2ORetireOrdersUpgradeable is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    struct Order {
        address buyer;
        uint256 rh2OAmount;
        address minter;
    }

    struct NewOrder {
        Order order;
        uint256 timestamp;
        bytes32 nonce;
    }

    bytes32 private constant NEW_ORDER_TYPEHASH =
        keccak256(
            "NewOrder(address buyer,uint256 rh2OAmount,address minter,uint256 timestamp,bytes32 nonce)"
        );

    IERC20 public rh2O;

    IMintersRegistry public mintersRegistry;
    IRetiredWaterCredit public retiredCredit;

    address public platformAddress;

    mapping(uint => Order) public orders;
    mapping(bytes32 => bool) public usedNonces;
    uint public orderCount;

    bool public isEmergency;

    event OrderCreated(
        uint orderId,
        address buyer,
        uint rh2OAmount,
        address minter,
        bytes32 nonce
    );
    event OrderCancelled(uint orderId, address canceller);
    event OrderFulfilled(uint orderId);

    event EmergencyModeSet(bool isEmergency);

    event RH2OContractsSet(
        address rh2O,
        address retiredCredit,
        address mintersRegistry
    );

    function initialize(
        address _rh2O,
        address _retiredCredit
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __EIP712_init("RH2ORetireOrders", "1");

        rh2O = IERC20(_rh2O);
        retiredCredit = IRetiredWaterCredit(_retiredCredit);

        mintersRegistry = IMintersRegistry(_rh2O);
    }

    modifier notEmergency() {
        require(!isEmergency, "Emergency");
        _;
    }

    function createOrder(
        NewOrder calldata newOrder,
        bytes calldata signature
    ) external nonReentrant notEmergency {
        validateOrder(newOrder, signature);
        require(newOrder.order.buyer == _msgSender(), "Invalid buyer");

        uint orderId = orderCount;

        orders[orderId].buyer = newOrder.order.buyer;
        orders[orderId].rh2OAmount = newOrder.order.rh2OAmount;
        orders[orderId].minter = newOrder.order.minter;

        usedNonces[newOrder.nonce] = true;

        orderCount += 1;

        emit OrderCreated(
            orderId,
            newOrder.order.buyer,
            newOrder.order.rh2OAmount,
            newOrder.order.minter,
            newOrder.nonce
        );
    }

    function cancelOrder(uint orderId) external nonReentrant notEmergency {
        require(orders[orderId].buyer != address(0), "Order doesn't exist");
        require(
            msg.sender == orders[orderId].buyer ||
                msg.sender == orders[orderId].minter,
            "Not allowed"
        );

        emit OrderCancelled(orderId, msg.sender);

        delete orders[orderId];
    }

    function fulfillOrder(uint orderId) external nonReentrant notEmergency {
        Order memory order = orders[orderId];

        require(order.buyer != address(0), "Order doesn't exist");
        require(msg.sender == order.minter, "Not allowed");

        require(
            rh2O.balanceOf(msg.sender) >= order.rh2OAmount,
            "Insufficient balance"
        );

        retiredCredit.retire(msg.sender, order.buyer, order.rh2OAmount);

        emit OrderFulfilled(orderId);

        delete orders[orderId];
    }

    function setEmergency(bool _isEmergency) external onlyOwner {
        isEmergency = _isEmergency;

        emit EmergencyModeSet(isEmergency);
    }

    function setPlatformAddress(address _platformAddress) external onlyOwner {
        platformAddress = _platformAddress;
    }

    function setup(
        address _rh2O,
        address _retiredCredit,
        address _mintersRegistry
    ) external onlyOwner {
        rh2O = IERC20(_rh2O);
        retiredCredit = IRetiredWaterCredit(_retiredCredit);
        mintersRegistry = IMintersRegistry(_mintersRegistry);

        emit RH2OContractsSet(_rh2O, _retiredCredit, _mintersRegistry);
    }

    function validateOrder(
        NewOrder calldata newOrder,
        bytes calldata signature
    ) public view returns (bool) {
        require(_validateSigner(newOrder, signature), "Signer invalid");
        require(!usedNonces[newOrder.nonce], "Nonce used");
        require(newOrder.order.rh2OAmount > 0, "Can't create 0 order");

        require(
            mintersRegistry.isMinter(newOrder.order.minter),
            "Not a registered minter"
        );

        require(
            newOrder.timestamp + 30 minutes >= block.timestamp,
            "Signature expired"
        );

        return true;
    }

    function _validateSigner(
        NewOrder calldata order,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 structHash = keccak256(
            abi.encode(
                NEW_ORDER_TYPEHASH,
                order.order.buyer,
                order.order.rh2OAmount,
                order.order.minter,
                order.timestamp,
                order.nonce
            )
        );
        address recoveredSignerAddress = ECDSA.recover(
            ECDSA.toTypedDataHash(_domainSeparatorV4(), structHash),
            signature
        );

        return recoveredSignerAddress == platformAddress;
    }
}


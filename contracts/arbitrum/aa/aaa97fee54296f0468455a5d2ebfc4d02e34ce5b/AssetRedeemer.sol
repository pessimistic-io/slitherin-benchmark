//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IFee.sol";
import "./IAssetTokenManager.sol";

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./ERC2771Context.sol";
import "./MinimalForwarder.sol";
import "./draft-IERC20Permit.sol";
import "./AccessControl.sol";
import "./SafeMath.sol";

contract AssetRedeemer is
    ERC2771Context,
    Ownable,
    Pausable,
    ReentrancyGuard,
    AccessControl
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bytes32 public constant GASLESS_ROLE = keccak256("GASLESS_ROLE");
    uint256 public constant MAX_UINT256 =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    event Redeem(
        uint256 id,
        address indexed sender,
        address output,
        uint256 outputAmount,
        address indexed asset,
        uint256 assetAmount,
        uint256 pricePerUnit,
        uint256 feeAmount,
        uint256 assetAmountForBroker
    );
    event Fulfill(
        uint256 id,
        address indexed user,
        address indexed relayer,
        address indexed asset,
        address output,
        uint256 assetAmount,
        uint256 pricePerUnit,
        uint256 feeAmount
    );
    event Reject(uint256 id);
    event Refund(uint256 id);
    event SetRelayer(address sender, address relayer);
    event SetFee(address sender, address to);
    event SetFeeReceiver(address sender, address to);
    event SetTimeout(address sender, uint256 timeout);

    enum OrderStatus {
        PENDING,
        FULFILLED,
        REJECTED,
        REFUND
    }

    struct Order {
        address sender;
        address asset;
        OrderStatus status;
        uint256 outputAmount;
        uint256 feeAmount;
        uint256 assetAmount;
        uint256 pricePerUnit;
        uint256 time;
        uint256 refundAmount;
        uint256 assetAmountForBroker;
    }

    address public relayer;
    address public fee;
    address public feeReceiver;
    address public immutable outputToken;
    IAssetTokenManager public immutable manager;
    uint256 public timeout; // after timeout user can refund pending orders
    uint256 public lastId; // starts from 1
    mapping(uint256 => Order) public orders;

    constructor(
        address _outputToken,
        address _manager,
        address _relayer,
        address _fee,
        address _feeReceiver,
        MinimalForwarder _trustedForwarder,
        uint256 _timeout
    ) ERC2771Context(address(_trustedForwarder)) {
        outputToken = _outputToken;
        manager = IAssetTokenManager(_manager);
        setRelayer(_relayer);
        setFee(_fee);
        setFeeReceiver(_feeReceiver);
        setTimeout(_timeout);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(GASLESS_ROLE, address(_trustedForwarder));
    }

    modifier onlyGaslessRole() {
        require(
            hasRole(GASLESS_ROLE, msg.sender),
            "AssetRedeemer: must have gasless role"
        );
        _;
    }

    function _msgSender()
        internal
        view
        virtual
        override(Context, ERC2771Context)
        returns (address sender)
    {
        return ERC2771Context._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(Context, ERC2771Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    function setRelayer(address _relayer) public onlyOwner {
        relayer = _relayer;
        emit SetRelayer(msg.sender, relayer);
    }

    function setFee(address _fee) public onlyOwner {
        fee = _fee;
        emit SetFee(msg.sender, fee);
    }

    function calculateFee(uint256 inputAmount) public view returns (uint256) {
        require(inputAmount > 0, "inputAmount must be greater than zero");
        if (fee == address(0)) {
            return 0;
        }
        return IFee(fee).calculate(inputAmount);
    }

    function setFeeReceiver(address _receiver) public onlyOwner {
        require(_receiver != address(0), "!receiver");
        feeReceiver = _receiver;
        emit SetFeeReceiver(msg.sender, feeReceiver);
    }

    modifier onlyRelayer() {
        require(msg.sender == relayer, "!relayer");
        _;
    }

    function setTimeout(uint256 _timeout) public onlyOwner {
        require(_timeout > 12 hours, "too short");
        timeout = _timeout;
        emit SetTimeout(msg.sender, timeout);
    }

    function roundDown(
        uint256 num,
        uint256 decimals
    ) public pure returns (uint256) {
        require(num > 0, "num must be greater than zero");
        require(decimals > 0, "decimals must be greater than zero");
        uint256 divisor = 10 ** decimals;
        return num.div(divisor).mul(divisor);
    }

    function calculateUsedOutputAmount(
        uint256 assetAmount,
        uint256 pricePerUnit
    ) public pure returns (uint256) {
        return assetAmount.mul(pricePerUnit).div(1 ether);
    }

    function redeem(
        address asset,
        uint256 assetAmount,
        uint256 pricePerUnit,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 deadline
    )
        external
        payable
        whenNotPaused
        nonReentrant
        onlyGaslessRole
        returns (uint256)
    {
        require(asset != address(0), "!asset");
        require(assetAmount > 0, "!amount");
        require(pricePerUnit > 0, "!price");
        require(manager.assets(asset), "!onlyAsset");

        uint256 outputAmount = calculateUsedOutputAmount(
            assetAmount,
            pricePerUnit
        );

        IERC20Permit(asset).permit(
            _msgSender(),
            address(this),
            MAX_UINT256,
            deadline,
            v,
            r,
            s
        );
        bool isOutputTokenEnough = manager.checkAssetReserver(
            outputToken,
            outputAmount
        );
        require(isOutputTokenEnough, "Token output reserve not enough");

        IERC20(asset).safeTransferFrom(
            _msgSender(),
            address(this),
            assetAmount
        );

        IERC20(asset).safeTransfer(manager.assetsReservers(asset), assetAmount);
        bool isAssetReserveEnoughForSell = manager.checkAssetReserver(
            asset,
            1 ether
        );

        lastId++;
        if (isAssetReserveEnoughForSell) {
            createOrder(asset, assetAmount, pricePerUnit, outputAmount);
        } else {
            fulfillOrder(asset, assetAmount, pricePerUnit, outputAmount);
        }

        return lastId;
    }

    function fulfillOrder(
        address asset,
        uint256 assetAmount,
        uint256 pricePerUnit,
        uint256 outputAmount
    ) internal whenNotPaused onlyGaslessRole {
        manager.withdrawFromReserver(address(this), outputToken, outputAmount);
        uint256 feeAmount = calculateFee(outputAmount);

        orders[lastId] = Order(
            _msgSender(),
            asset,
            OrderStatus.FULFILLED,
            outputAmount,
            feeAmount,
            assetAmount,
            pricePerUnit,
            block.timestamp,
            0, // refundAmount
            0 // assetAmountForBroker
        );

        IERC20(outputToken).safeTransfer(feeReceiver, feeAmount);
        IERC20(outputToken).safeTransfer(
            _msgSender(),
            outputAmount.sub(feeAmount)
        );

        emit Fulfill(
            lastId,
            _msgSender(),
            relayer,
            asset,
            outputToken,
            assetAmount,
            pricePerUnit,
            feeAmount
        );
    }

    function createOrder(
        address asset,
        uint256 assetAmount,
        uint256 pricePerUnit,
        uint256 outputAmount
    ) internal whenNotPaused onlyGaslessRole {
        uint256 assetReserveBalance = IERC20(asset).balanceOf(
            manager.assetsReservers(asset)
        );
        uint256 assetAmountForBroker = roundDown(assetReserveBalance, 18);

        uint256 feeAmount = 0;
        orders[lastId] = Order(
            _msgSender(),
            asset,
            OrderStatus.PENDING,
            outputAmount,
            feeAmount, // fee
            assetAmount,
            pricePerUnit,
            block.timestamp,
            0, // refundAmount
            assetAmountForBroker // assetAmountForBroker
        );

        manager.withdrawFromReserver(
            address(this),
            asset,
            assetAmountForBroker
        );

        emit Redeem(
            lastId,
            _msgSender(),
            outputToken,
            outputAmount,
            asset,
            assetAmount,
            pricePerUnit,
            feeAmount, // fee
            assetAmountForBroker // assetAmountForBroker
        );
    }

    function fulfill(
        uint256 id,
        uint256 pricePerUnit
    ) external whenNotPaused onlyRelayer {
        Order storage order = orders[id];
        require(order.status == OrderStatus.PENDING, "!pending");
        require(pricePerUnit >= order.pricePerUnit, "!price");

        uint256 outputAmount = calculateUsedOutputAmount(
            order.assetAmount,
            pricePerUnit
        );

        bool isOutputTokenEnough = manager.checkAssetReserver(
            outputToken,
            outputAmount
        );

        require(isOutputTokenEnough, "Token output reserve not enough");

        order.status = OrderStatus.FULFILLED;

        IERC20(order.asset).approve(
            address(manager),
            order.assetAmountForBroker
        );
        manager.burn(order.asset, order.assetAmountForBroker);

        manager.withdrawFromReserver(address(this), outputToken, outputAmount);

        uint256 feeAmount = calculateFee(outputAmount);
        order.feeAmount = feeAmount;

        IERC20(outputToken).safeTransfer(feeReceiver, feeAmount);

        IERC20(outputToken).safeTransfer(
            order.sender,
            outputAmount.sub(feeAmount)
        );

        emit Fulfill(
            id,
            order.sender,
            msg.sender,
            order.asset,
            outputToken,
            order.assetAmount,
            pricePerUnit,
            feeAmount
        );
    }

    function reject(uint256 id) external onlyRelayer {
        Order storage order = orders[id];
        require(order.status == OrderStatus.PENDING, "!pending");
        order.status = OrderStatus.REJECTED;

        IERC20(order.asset).safeTransfer(
            manager.assetsReservers(order.asset),
            order.assetAmountForBroker.sub(order.assetAmount)
        );
        IERC20(order.asset).safeTransfer(order.sender, order.assetAmount);

        emit Reject(id);
    }

    function refund(uint256 id) external nonReentrant {
        Order storage order = orders[id];
        require(order.status == OrderStatus.PENDING, "!pending");
        require(order.sender == msg.sender, "!sender");
        require(block.timestamp > order.time + timeout, "!timeout");
        order.status = OrderStatus.REFUND;

        IERC20(order.asset).safeTransfer(
            manager.assetsReservers(order.asset),
            order.assetAmountForBroker.sub(order.assetAmount)
        );
        IERC20(order.asset).safeTransfer(order.sender, order.assetAmount);

        emit Refund(id);
    }

    function refundGasless(uint256 id) external onlyGaslessRole {
        Order storage order = orders[id];
        require(order.status == OrderStatus.PENDING, "!pending");
        require(order.sender == _msgSender(), "!sender");
        require(block.timestamp > order.time + timeout, "!timeout");
        order.status = OrderStatus.REFUND;

        IERC20(order.asset).safeTransfer(
            manager.assetsReservers(order.asset),
            order.assetAmountForBroker.sub(order.assetAmount)
        );
        IERC20(order.asset).safeTransfer(order.sender, order.assetAmount);

        emit Refund(id);
    }

    function pause() external onlyOwner {
        _pause();
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit Unpaused(msg.sender);
    }
}


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

contract AssetMinter is
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

    event Mint(
        uint256 id,
        address indexed sender,
        address input,
        uint256 inputAmount,
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
        address input,
        uint256 assetAmount,
        uint256 pricePerUnit,
        uint256 refundAmount
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
        uint256 inputAmount;
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
    address public immutable inputToken;
    IAssetTokenManager public immutable manager;
    uint256 public timeout; // after timeout user can refund pending orders
    uint256 public lastId; // starts from 1
    mapping(uint256 => Order) public orders;

    constructor(
        address _inputToken,
        address _manager,
        address _relayer,
        address _fee,
        address _feeReceiver,
        MinimalForwarder _trustedForwarder,
        uint256 _timeout
    ) ERC2771Context(address(_trustedForwarder)) {
        inputToken = _inputToken;
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
            "AssetMinter: must have gasless role"
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

    modifier onlyRelayer() {
        require(msg.sender == relayer, "!relayer");
        _;
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

    function roundUp(
        uint256 num,
        uint256 decimals
    ) public pure returns (uint256) {
        require(num > 0, "num must be greater than zero");
        require(decimals > 0, "decimals must be greater than zero");
        uint256 divisor = 10 ** decimals;
        uint256 remainder = num.mod(divisor);
        if (remainder == 0) {
            return num;
        } else {
            return num.add(divisor).sub(remainder);
        }
    }

    function setFeeReceiver(address _receiver) public onlyOwner {
        require(_receiver != address(0), "!receiver");
        feeReceiver = _receiver;
        emit SetFeeReceiver(msg.sender, feeReceiver);
    }

    function setTimeout(uint256 _timeout) public onlyOwner {
        require(_timeout > 12 hours, "too short");
        timeout = _timeout;
        emit SetTimeout(msg.sender, timeout);
    }

    function calculateUsedInputAmount(
        uint256 assetAmount,
        uint256 pricePerUnit
    ) public pure returns (uint256) {
        return assetAmount.mul(pricePerUnit).div(1 ether);
    }

    function mint(
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

        uint256 inputAmount = calculateUsedInputAmount(
            assetAmount,
            pricePerUnit
        );
        uint256 feeAmount = calculateFee(inputAmount);

        IERC20Permit(inputToken).permit(
            _msgSender(),
            address(this),
            MAX_UINT256,
            deadline,
            v,
            r,
            s
        );

        IERC20(inputToken).safeTransferFrom(
            _msgSender(),
            address(this),
            inputAmount.add(feeAmount)
        );

        bool isEnough = manager.checkAssetReserver(asset, assetAmount);
        lastId++;
        if (isEnough) {
            fulfillOrder(
                asset,
                assetAmount,
                pricePerUnit,
                inputAmount,
                feeAmount
            );
        } else {
            createOrder(
                asset,
                assetAmount,
                pricePerUnit,
                inputAmount,
                feeAmount
            );
        }

        return lastId;
    }

    function fulfillOrder(
        address asset,
        uint256 assetAmount,
        uint256 pricePerUnit,
        uint256 inputAmount,
        uint256 feeAmount
    ) internal whenNotPaused {
        manager.withdrawFromReserver(address(this), asset, assetAmount);

        orders[lastId] = Order(
            _msgSender(),
            asset,
            OrderStatus.FULFILLED,
            inputAmount,
            feeAmount,
            assetAmount,
            pricePerUnit,
            block.timestamp,
            0,
            0
        );

        IERC20(inputToken).safeTransfer(
            manager.assetsReservers(inputToken),
            inputAmount
        );
        IERC20(inputToken).safeTransfer(feeReceiver, feeAmount);
        IERC20(asset).safeTransfer(_msgSender(), assetAmount);

        emit Fulfill(
            lastId,
            _msgSender(),
            relayer,
            asset,
            inputToken,
            assetAmount,
            pricePerUnit,
            0
        );
    }

    function createOrder(
        address asset,
        uint256 assetAmount,
        uint256 pricePerUnit,
        uint256 inputAmount,
        uint256 feeAmount
    ) internal whenNotPaused {
        uint256 assetAmountForBroker = roundUp(assetAmount, 18);

        orders[lastId] = Order(
            _msgSender(),
            asset,
            OrderStatus.PENDING,
            inputAmount,
            feeAmount,
            assetAmount,
            pricePerUnit,
            block.timestamp,
            0,
            assetAmountForBroker
        );

        emit Mint(
            lastId,
            _msgSender(),
            inputToken,
            inputAmount,
            asset,
            assetAmount,
            pricePerUnit,
            feeAmount,
            assetAmountForBroker
        );
    }

    function fulfill(
        uint256 id,
        uint256 pricePerUnit
    ) external whenNotPaused onlyRelayer {
        Order storage order = orders[id];
        require(order.status == OrderStatus.PENDING, "!pending");
        require(pricePerUnit <= order.pricePerUnit, "!price");
        order.status = OrderStatus.FULFILLED;

        uint256 useAmount = calculateUsedInputAmount(
            order.assetAmount,
            pricePerUnit
        );
        uint256 refundAmount = order.inputAmount.sub(useAmount);
        order.refundAmount = refundAmount;

        IERC20(inputToken).safeTransfer(
            manager.assetsReservers(inputToken),
            useAmount
        );
        IERC20(inputToken).safeTransfer(feeReceiver, order.feeAmount);
        if (refundAmount > 0) {
            IERC20(inputToken).safeTransfer(order.sender, refundAmount);
        }

        uint256 amountScrap = order.assetAmountForBroker.sub(order.assetAmount);
        manager.mintForReserver(order.asset, amountScrap);
        manager.mint(order.asset, order.assetAmount);
        IERC20(order.asset).safeTransfer(order.sender, order.assetAmount);

        emit Fulfill(
            id,
            order.sender,
            msg.sender,
            order.asset,
            inputToken,
            order.assetAmount,
            pricePerUnit,
            refundAmount
        );
    }

    function reject(uint256 id) external onlyRelayer {
        Order storage order = orders[id];
        require(order.status == OrderStatus.PENDING, "!pending");
        order.status = OrderStatus.REJECTED;

        order.refundAmount = order.inputAmount.add(order.feeAmount);
        IERC20(inputToken).safeTransfer(order.sender, order.refundAmount);

        emit Reject(id);
    }

    function refund(uint256 id) external nonReentrant {
        Order storage order = orders[id];
        require(order.status == OrderStatus.PENDING, "!pending");
        require(order.sender == msg.sender, "!sender");
        require(block.timestamp > order.time + timeout, "!timeout");
        order.status = OrderStatus.REFUND;

        order.refundAmount = order.inputAmount.add(order.feeAmount);
        IERC20(inputToken).safeTransfer(order.sender, order.refundAmount);

        emit Refund(id);
    }

    function refundGasless(uint256 id) external onlyGaslessRole {
        Order storage order = orders[id];
        require(order.status == OrderStatus.PENDING, "!pending");
        require(order.sender == _msgSender(), "!sender");
        require(block.timestamp > order.time + timeout, "!timeout");
        order.status = OrderStatus.REFUND;

        order.refundAmount = order.inputAmount.add(order.feeAmount);
        IERC20(inputToken).safeTransfer(order.sender, order.refundAmount);

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


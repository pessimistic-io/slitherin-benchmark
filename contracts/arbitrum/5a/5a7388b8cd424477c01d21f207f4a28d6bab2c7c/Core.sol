// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./ICore.sol";

contract Core is ICore, Ownable, ReentrancyGuard {
    uint256 public constant DIVIDER = 1 ether;
    uint256 public constant CANCELATION_PERIOD = 15 minutes; // TODO: need set production value

    ICoreConfiguration.ImmutableConfiguration private _immutableConfiguration;
    Counters private _counters;
    mapping(uint256 => Position) private _positions;
    mapping(uint256 => Order) private _orders;

    ICoreConfiguration public immutable configuration;
    address public immutable permitPeriphery;
    mapping(uint256 => uint256) public positionIdToOrderId;
    mapping(address => uint256[]) public creatorToOrders;
    mapping(uint256 => uint256[]) public orderIdToPositions;

    function counters() external view returns (Counters memory) {
        return _counters;
    }

    function creatorOrdersCount(address creator) external view returns (uint256) {
        return creatorToOrders[creator].length;
    }

    function availableFeeAmount() public view returns (uint256) {
        return _immutableConfiguration.stable.balanceOf(address(this)) - _counters.totalStableAmount;
    }

    function orderIdPositionsCount(uint256 orderId) external view returns (uint256) {
        return orderIdToPositions[orderId].length;
    }

    function positions(uint256 id) external view returns (Position memory) {
        return _positions[id];
    }

    function orders(uint256 id) external view returns (Order memory) {
        return _orders[id];
    }

    constructor(address configuration_, address permitPeriphery_) {
        require(configuration_ != address(0), "Core: Configuration is zero address");
        require(permitPeriphery_ != address(0), "Core: PermitPeriphery is zero address");
        configuration = ICoreConfiguration(configuration_);
        (
            IFoxifyBlacklist blacklist,
            IFoxifyAffiliation affiliation,
            IPositionToken positionTokenAccepter,
            IERC20Stable stable
        ) = configuration.immutableConfiguration();
        _immutableConfiguration = ICoreConfiguration.ImmutableConfiguration(
            blacklist,
            affiliation,
            positionTokenAccepter,
            stable
        );
        permitPeriphery = permitPeriphery_;
    }

    function accept(
        address accepter,
        uint256 orderId,
        uint256 amount
    ) external nonReentrant notBlacklisted(accepter) returns (uint256 positionId) {
        if (msg.sender != permitPeriphery) accepter = msg.sender;
        ICoreConfiguration configuration_ = configuration;
        require(orderId > 0 && orderId <= _counters.ordersCount, "Core: Invalid order id");
        (uint256 minStableAmount,,,,) = configuration_.limitsConfiguration();
        require(amount > minStableAmount, "Core: Amount lt min value");
        Order storage order_ = _orders[orderId];
        require(!order_.closed, "Core: Order is closed");
        require(configuration_.oraclesWhitelistContains(order_.data.oracle), "Core: Oracle not whitelisted");
        Counters storage counters_ = _counters;
        counters_.positionsCount++;
        positionId = counters_.positionsCount;
        positionIdToOrderId[positionId] = orderId;
        orderIdToPositions[orderId].push(positionId);
        Position storage position_ = _positions[positionId];
        position_.startTime = block.timestamp;
        position_.endTime = block.timestamp + order_.data.duration;
        IOracleConnector oracle_ = IOracleConnector(order_.data.oracle);
        require(oracle_.validateTimestamp(position_.endTime), "Core: Position end time not supported");
        position_.startPrice = oracle_.getPrice();
        (,,position_.protocolFee,) = configuration_.feeConfiguration();
        position_.amountAccepter = amount;
        position_.amountCreator = (amount * order_.data.rate) / DIVIDER;
        position_.status = PositionStatus.PENDING;
        position_.deviationPrice = (position_.startPrice * order_.data.percent) / DIVIDER;
        require(position_.amountCreator <= order_.available, "Core: Insufficient creator balance");
        order_.available -= position_.amountCreator;
        order_.reserved += position_.amountCreator;
        counters_.totalStableAmount += amount;
        _immutableConfiguration.stable.transferFrom(msg.sender, address(this), amount);
        _immutableConfiguration.positionTokenAccepter.mint(accepter, positionId);
        emit Accepted(orderId, positionId, order_, position_, amount);
    }

    function autoResolve(uint256 positionId) external returns (bool) {
        require(configuration.keepersContains(msg.sender), "Core: Caller is not keeper");
        require(positionId > 0 && positionId <= _counters.positionsCount, "Core: Invalid position id");
        Order storage order_ = _orders[positionIdToOrderId[positionId]];
        Position storage position_ = _positions[positionId];
        require(position_.status == PositionStatus.PENDING, "Core: Auto resolve completed");
        require(position_.endTime <= block.timestamp, "Core: Position is active");
        position_.endPrice = IOracleConnector(order_.data.oracle).getPrice();
        address creator = order_.creator;
        address accepter = _immutableConfiguration.positionTokenAccepter.ownerOf(positionId);
        uint256 protocolStableFee = 0;
        uint256 autoResolveFee = 0;
        uint256 amountCreator = 0;
        uint256 amountAccepter = 0;
        order_.reserved -= position_.amountCreator;
        if (
            position_.endTime + CANCELATION_PERIOD <= block.timestamp
            || !configuration.oraclesWhitelistContains(order_.data.oracle)
        ) {
            order_.available += position_.amountCreator;
            amountAccepter = position_.amountAccepter;
            _counters.totalStableAmount -= amountAccepter;
            position_.status = PositionStatus.CANCELED;
        } else {
            uint256 gain = 0;
            if (
                (order_.data.direction == OrderDirectionType.UP && position_.endPrice >= position_.deviationPrice) ||
                (order_.data.direction == OrderDirectionType.DOWN && position_.endPrice <= position_.deviationPrice)
            ) {
                position_.winner = creator;
                gain = position_.amountAccepter;
            } else {
                position_.winner = accepter;
                gain = position_.amountCreator;
            }
            autoResolveFee = _swap(msg.sender, gain);
            protocolStableFee = _calculateStableFee(position_.winner, gain, position_.protocolFee);
            uint256 residual = gain - autoResolveFee;
            if (residual < protocolStableFee) protocolStableFee = residual;
            uint256 totalStableFee = protocolStableFee + autoResolveFee;
            _counters.totalStableAmount -= totalStableFee;
            gain -= totalStableFee;
            position_.status = PositionStatus.EXECUTED;
            if (position_.winner == creator) {
                order_.available += position_.amountCreator;
                if (gain > 0) {
                    if (order_.data.reinvest) {
                        order_.amount += gain;
                        order_.available += gain;
                    } else {
                        _counters.totalStableAmount -= gain;
                        amountCreator = gain;
                    }
                }
            } else {
                uint256 total = position_.amountAccepter + gain;
                order_.amount -= position_.amountCreator;
                _counters.totalStableAmount -= total;
                amountAccepter = total;
            }
        }
        _immutableConfiguration.positionTokenAccepter.burn(positionId);
        if (amountCreator > 0) _immutableConfiguration.stable.transfer(creator, amountCreator);
        if (amountAccepter > 0) _immutableConfiguration.stable.transfer(accepter, amountAccepter);
        emit AutoResolved(
            positionIdToOrderId[positionId],
            positionId,
            position_.winner,
            protocolStableFee,
            autoResolveFee
        );
        return true;
    }

    function closeOrder(uint256 orderId) external returns (bool) {
        require(orderId > 0 && orderId <= _counters.ordersCount, "Core: Invalid order id");
        Order storage order_ = _orders[orderId];
        require(order_.creator == msg.sender, "Core: Caller is not creator");
        order_.closed = true;
        emit OrderClosed(orderId, order_);
        return true;
    }

    function claimFee(uint256 amount) external onlyOwner returns (bool) {
        IERC20Stable stable_ = _immutableConfiguration.stable;
        require(amount <= availableFeeAmount(), "Core: Amount gt available");
        (address feeRecipient,,,) = configuration.feeConfiguration();
        stable_.transfer(feeRecipient, amount);
        emit FeeClaimed(amount);
        return true;
    }

    function createOrder(
        address creator,
        OrderDescription memory data,
        uint256 amount
    ) external nonReentrant notBlacklisted(creator) returns (uint256 orderId) {
        if (msg.sender != permitPeriphery) creator = msg.sender;
        ICoreConfiguration configuration_ = configuration;
        (
            ,uint256 minOrderRate,
            uint256 maxOrderRate,
            uint256 minDuration,
            uint256 maxDuration
        ) = configuration_.limitsConfiguration();
        require(data.rate >= minOrderRate && data.rate <= maxOrderRate, "Core: Position rate is invalid");
        require(data.duration >= minDuration && data.duration <= maxDuration, "Core: Duration is invalid");
        require(configuration_.oraclesWhitelistContains(data.oracle), "Core: Oracle not whitelisted");
        if (data.direction == OrderDirectionType.DOWN) require(data.percent < DIVIDER, "Core: Percent gt DIVIDER");
        else require(data.percent > DIVIDER, "Core: Percent lt DIVIDER");
        Counters storage counters_ = _counters;
        counters_.ordersCount++;
        orderId = counters_.ordersCount;
        Order storage order_ = _orders[orderId];
        order_.data = data;
        order_.creator = creator;
        order_.amount = amount;
        order_.available = amount;
        creatorToOrders[creator].push(orderId);
        counters_.totalStableAmount += amount;
        if (amount > 0) _immutableConfiguration.stable.transferFrom(msg.sender, address(this), amount);
        emit OrderCreated(orderId, order_);
    }

    function flashloan(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant notBlacklisted(msg.sender) returns (bool) {
        IERC20Stable stable = _immutableConfiguration.stable;
        uint256 balanceBefore = stable.balanceOf(address(this));
        require(amount > 0 && amount <= balanceBefore, "Core: Invalid amount");
        (,,,uint256 flashloanFee) = configuration.feeConfiguration();
        uint256 fee = _calculateStableFee(msg.sender, amount, flashloanFee);
        stable.transfer(recipient, amount);
        IOptionsFlashCallback(msg.sender).optionsFlashCallback(recipient, amount, fee, data);
        uint256 balanceAfter = stable.balanceOf(address(this));
        require(balanceBefore + fee <= balanceAfter, "Core: Invalid stable balance");
        emit Flashloan(msg.sender, recipient, amount, balanceAfter - balanceBefore);
        return true;
    }

    function increaseOrder(
        uint256 orderId,
        uint256 amount
    ) external nonReentrant notBlacklisted(msg.sender) returns (bool) {
        Counters storage counters_ = _counters;
        require(orderId > 0 && orderId <= counters_.ordersCount, "Core: Invalid order id");
        require(amount > 0, "Core: Amount is not positive");
        Order storage order_ = _orders[orderId];
        require(msg.sender == order_.creator, "Core: Caller is not creator");
        require(!order_.closed, "Core: Order is closed");
        order_.amount += amount;
        order_.available += amount;
        counters_.totalStableAmount += amount;
        _immutableConfiguration.stable.transferFrom(msg.sender, address(this), amount);
        emit OrderIncreased(orderId, amount);
        return true;
    }

    function withdrawOrder(uint256 orderId, uint256 amount) external nonReentrant returns (bool) {
        Counters storage counters_ = _counters;
        require(orderId > 0 && orderId <= counters_.ordersCount, "Core: Invalid order id");
        require(amount > 0, "Core: Amount is not positive");
        Order storage order_ = _orders[orderId];
        require(msg.sender == order_.creator, "Core: Caller is not creator");
        require(amount <= order_.available, "Core: Amount gt available");
        order_.amount -= amount;
        order_.available -= amount;
        counters_.totalStableAmount -= amount;
        _immutableConfiguration.stable.transfer(msg.sender, amount);
        emit OrderWithdrawal(orderId, amount);
        return true;
    }

    function _calculateStableFee(
        address affiliationUser,
        uint256 amount,
        uint256 fee
    ) private view returns (uint256) {
        IFoxifyAffiliation affiliation = _immutableConfiguration.affiliation;
        (uint256 bronze, uint256 silver, uint256 gold) = configuration.discount();
        AffiliationUserData memory affiliationUserData_;
        affiliationUserData_.activeId = affiliation.usersActiveID(affiliationUser);
        affiliationUserData_.team = affiliation.usersTeam(affiliationUser);
        affiliationUserData_.nftData = affiliation.data(affiliationUserData_.activeId);
        IFoxifyAffiliation.Level level = affiliationUserData_.nftData.level;
        if (level == IFoxifyAffiliation.Level.BRONZE) {
            affiliationUserData_.discount = bronze;
        } else if (level == IFoxifyAffiliation.Level.SILVER) {
            affiliationUserData_.discount = silver;
        } else if (level == IFoxifyAffiliation.Level.GOLD) {
            affiliationUserData_.discount = gold;
        }
        uint256 stableFee = (amount * fee) / DIVIDER;
        uint256 discount_ = (affiliationUserData_.discount * stableFee) / DIVIDER;
        return stableFee - discount_;
    }

    function _swap(address recipient, uint256 winnerTotalAmount) private returns (uint256 amountIn) {
        (ISwapperConnector swapperConnector, bytes memory path) = configuration.swapper();
        IERC20Stable stable = _immutableConfiguration.stable;
        (, uint256 autoResolveFee_,,) = configuration.feeConfiguration();
        amountIn = swapperConnector.getAmountIn(path, autoResolveFee_);
        if (amountIn > winnerTotalAmount) amountIn = winnerTotalAmount;
        stable.approve(address(swapperConnector), amountIn);
        swapperConnector.swap(path, address(stable), amountIn, recipient);
    }

    modifier notBlacklisted(address user) {
        require(!_immutableConfiguration.blacklist.blacklistContains(user), "Core: Address blacklisted");
        _;
    }
}


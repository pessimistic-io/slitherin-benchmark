// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
pragma abicoder v2;
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./Dev.sol";
import "./Common.sol";
import "./Fee.sol";

abstract contract Mint is Dev, Fee, Common {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private whitelistUser;
    struct MintPool {
        uint256 startAt;
        uint256 endAt;
        uint256 unitPrice; // eth
        uint256 sendPer; // The number of tokens that will be received
        uint256 totalQuota; // total quota
        uint256 perUserQuota; // user quota
        uint256 soldQuota; // Sold quota
    }
    MintPool public whitelistPool;
    MintPool public openPool;
    mapping(address => uint256) public whitelistMints;
    mapping(address => uint256) public openMints;

    event Mints(
        uint8 indexed source,
        address indexed user,
        uint256 totalAmount,
        uint256 quota,
        uint256 receiveAmount
    );

    function mintWhitelist(uint256 quota) external payable {
        require(whitelistPool.startAt < block.timestamp, "WL: mint not start");
        require(whitelistPool.endAt > block.timestamp, "WL: mint ended");
        require(isWhitelistUser(_msgSender()), "WL: not whitelist user");
        require(quota > 0, "WL: must greater than 0");
        require(
            (whitelistMints[_msgSender()] + quota) <=
                whitelistPool.perUserQuota,
            "WL: Insufficient quota"
        );
        require(
            quota <= whitelistPool.totalQuota - whitelistPool.soldQuota,
            "WL: Insufficient total quota"
        );
        require(
            msg.value >= quota * whitelistPool.unitPrice,
            "WL: Not enough ETH sent"
        );
        whitelistPool.soldQuota += quota;
        whitelistMints[_msgSender()] += quota;
        payable(owner()).transfer(msg.value);
        uint256 tax = _calcPercent(
            quota * whitelistPool.sendPer,
            _sellTotalFee()
        );
        uint256 sendTotal = quota * whitelistPool.sendPer - tax;
        _innerTransfer(address(this), _msgSender(), sendTotal);
        _innerTransfer(address(this), devAddress, tax);
        emit Mints(
            1,
            _msgSender(),
            quota * whitelistPool.unitPrice,
            quota,
            sendTotal
        );
    }

    function mintOpen(uint256 quota) external payable {
        require(openPool.startAt < block.timestamp, "OP: mint not start");
        require(openPool.endAt > block.timestamp, "OP: mint not start");
        require(quota > 0, "OP: must greater than 0");
        require(
            (openMints[_msgSender()] + quota) <= openPool.perUserQuota,
            "WL: Insufficient quota"
        );
        require(
            quota <= openPool.totalQuota - openPool.soldQuota,
            "OP: Insufficient total quota"
        );
        uint256 totalPrice = (quota *
            openPool.unitPrice *
            (isWhitelistUser(_msgSender()) ? 80 : 100)) / 100;
        require(msg.value >= totalPrice, "OP: Not enough ETH sent");
        openPool.soldQuota += quota;
        openMints[_msgSender()] += quota;
        payable(owner()).transfer(msg.value);
        uint256 tax = _calcPercent(quota * openPool.sendPer, _sellTotalFee());
        uint256 sendTotal = quota * openPool.sendPer - tax;
        _innerTransfer(address(this), _msgSender(), sendTotal);
        _innerTransfer(address(this), devAddress, tax);
        emit Mints(2, _msgSender(), totalPrice, quota, sendTotal);
    }

    function setWhitelistMintPool(
        uint256 startAt,
        uint256 endAt,
        uint256 unitPrice,
        uint256 sendPer,
        uint256 totalQuota,
        uint256 perUserQuota
    ) external onlyManger {
        whitelistPool.startAt = startAt;
        whitelistPool.endAt = endAt;
        whitelistPool.unitPrice = unitPrice;
        whitelistPool.sendPer = sendPer;
        whitelistPool.totalQuota = totalQuota;
        whitelistPool.perUserQuota = perUserQuota;
        whitelistPool.soldQuota = 0;
    }

    function setOpenMintPool(
        uint256 startAt,
        uint256 endAt,
        uint256 unitPrice,
        uint256 sendPer,
        uint256 totalQuota,
        uint256 perUserQuota
    ) external onlyManger {
        openPool.startAt = startAt;
        openPool.endAt = endAt;
        openPool.unitPrice = unitPrice;
        openPool.sendPer = sendPer;
        openPool.totalQuota = totalQuota;
        openPool.perUserQuota = perUserQuota;
        openPool.soldQuota = 0;
    }

    function getWhitelistUser()
        external
        view
        returns (address[] memory accounts)
    {
        return whitelistUser.values();
    }

    function isWhitelistUser(address account) public view returns (bool) {
        return whitelistUser.contains(account);
    }

    function addWhitelistUser(address[] memory accounts) external onlyManger {
        for (uint256 i = 0; i < accounts.length; i++) {
            _addWhitelistUser(accounts[i]);
        }
    }

    function removeWhitelistUser(
        address[] memory accounts
    ) external onlyManger {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelistUser.remove(accounts[i]);
        }
    }

    function _addWhitelistUser(address account) internal {
        whitelistUser.add(account);
    }
}


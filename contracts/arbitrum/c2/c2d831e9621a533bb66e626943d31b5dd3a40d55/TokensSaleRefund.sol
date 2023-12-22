// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./ReentrancyGuard.sol";
import "./ITokensSale.sol";
import "./ITokensVesting.sol";

contract TokensSaleRefund is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct BatchInfo {
        uint256 start;
        uint256 end;
    }

    enum BatchStatus {
        INACTIVE,
        ACTIVE
    }

    ITokensSale public tokensSale;
    ITokensVesting public tokensVesting;
    mapping(uint256 batchNumber => BatchInfo) public batchInfos;
    mapping(uint256 batchNumber => BatchStatus) public batchStatus;
    mapping(uint256 batchNumber => mapping(address user => bool)) public refunded;

    EnumerableSet.UintSet private _batches;
    mapping(uint256 => EnumerableSet.AddressSet) private _whitelistAddresses;

    event BatchStatusUpdated(uint256 indexed batchNumber, uint8 status);
    event BatchUpdated(uint256 indexed batchNumber, uint256 start, uint256 end);
    event WhitelistAddressAdded(
        uint256 indexed batchNumber,
        address indexed user
    );
    event WhitelistAddressRemoved(
        uint256 indexed batchNumber,
        address indexed user
    );
    event Refund(address user, uint256 amount);

    modifier batchExisted(uint256 batchNumber) {
        require(
            _batches.contains(batchNumber),
            "TokensSaleRefund: batchNumber does not exist"
        );
        _;
    }

    constructor(address tokensSale_) {
        tokensSale = ITokensSale(tokensSale_);
        tokensVesting = ITokensVesting(tokensSale.tokensVesting());
    }

    function refund(
        uint256 batchNumber
    ) external nonReentrant batchExisted(batchNumber) {
        require(
            batchStatus[batchNumber] == BatchStatus.ACTIVE,
            "TokensSaleRefund: the sale is inactive"
        );

        BatchInfo storage refundBatchInfo = batchInfos[batchNumber];
        require(
            block.timestamp >= refundBatchInfo.start,
            "TokensSaleRefund: the refund does not start"
        );
        require(
            block.timestamp < refundBatchInfo.end || refundBatchInfo.end == 0,
            "TokensSale: the refund is ended"
        );

        address user = msg.sender;
        require(
            !refunded[batchNumber][user],
            "TokensSaleRefund: already refunded"
        );

        if (_whitelistAddresses[batchNumber].length() > 0) {
            require(
                _whitelistAddresses[batchNumber].contains(user),
                "TokensSaleRefund: sender is not in whitelist"
            );
        }

        refunded[batchNumber][user] = true;

        ITokensSale.UserInfo memory userInfo = tokensSale.userInfos(
            batchNumber,
            user
        );

        require(
            userInfo.paymentAmount > 0,
            "TokensSaleRefund: user not joined"
        );
        require(
            userInfo.harvested,
            "TokensSaleRefund: please harvest before refund"
        );

        tokensVesting.revokeTokensOfAddress(user);

        ITokensSale.BatchSaleInfo memory batchInfo = tokensSale.batchSaleInfos(
            batchNumber
        );
        IERC20(batchInfo.paymentToken).safeTransfer(
            user,
            userInfo.paymentAmount
        );

        emit Refund(user, userInfo.paymentAmount);
    }

    function withdrawERC20Tokens(
        address token,
        uint256 amount
    ) external nonReentrant onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function addWhitelistAddressToBatch(
        uint256 batchNumber,
        address whitelistAddress
    ) external onlyOwner batchExisted(batchNumber) {
        require(
            _whitelistAddresses[batchNumber].add(whitelistAddress),
            "TokensSaleRefund: address is already in whitelist"
        );
    }

    function addWhitelistAddressesToBatch(
        uint256 batchNumber,
        address[] calldata whitelistAddress
    ) external onlyOwner batchExisted(batchNumber) {
        require(
            whitelistAddress.length > 0,
            "TokensSaleRefund: whitelistAddress is empty"
        );
        for (uint256 index = 0; index < whitelistAddress.length; index++) {
            require(
                _whitelistAddresses[batchNumber].add(whitelistAddress[index]),
                "TokensSaleRefund: address is already in whitelist"
            );
            emit WhitelistAddressAdded(batchNumber, whitelistAddress[index]);
        }
    }

    function removeWhitelistAddressOutBatch(
        uint256 batchNumber,
        address whitelistAddress
    ) external onlyOwner batchExisted(batchNumber) {
        require(
            _whitelistAddresses[batchNumber].remove(whitelistAddress),
            "TokensSaleRefund: address is not in whitelist"
        );
    }

    function removeWhitelistAddressesOutBatch(
        uint256 batchNumber,
        address[] calldata whitelistAddresses
    ) external onlyOwner batchExisted(batchNumber) {
        require(
            whitelistAddresses.length > 0,
            "TokensSaleRefund: whitelistAddresses is empty"
        );
        for (uint256 index = 0; index < whitelistAddresses.length; index++) {
            require(
                _whitelistAddresses[batchNumber].remove(
                    whitelistAddresses[index]
                ),
                "TokensSaleRefund: address is not in whitelist or already removed"
            );
            emit WhitelistAddressRemoved(
                batchNumber,
                whitelistAddresses[index]
            );
        }
    }

    function getWhitelistAddresses(
        uint256 batchNumber
    ) public view returns (address[] memory) {
        return _whitelistAddresses[batchNumber].values();
    }

    function batches() public view returns (uint256[] memory) {
        return _batches.values();
    }

    function updateBatchStatus(
        uint256 batchNumber,
        uint8 status
    ) external onlyOwner batchExisted(batchNumber) {
        if (batchStatus[batchNumber] != BatchStatus(status)) {
            batchStatus[batchNumber] = BatchStatus(status);
            emit BatchStatusUpdated(batchNumber, status);
        } else {
            revert("TokensSaleRefund: status is same as before");
        }
    }

    function addBatch(
        uint256 batchNumber,
        uint256 start,
        uint256 end
    ) external onlyOwner {
        require(batchNumber > 0, "TokensSaleRefund: batchNumber is 0");
        require(
            _batches.add(batchNumber),
            "TokensSaleRefund: batchNumber already existed"
        );

        batchStatus[batchNumber] = BatchStatus.ACTIVE;
        _updateBatchInfo(batchNumber, start, end);
    }

    function updateBatchInfo(
        uint256 batchNumber,
        uint256 start,
        uint256 end
    ) external onlyOwner batchExisted(batchNumber) {
        _updateBatchInfo(batchNumber, start, end);
    }

    function _updateBatchInfo(
        uint256 batchNumber,
        uint256 start,
        uint256 end
    ) private {
        BatchInfo storage info = batchInfos[batchNumber];
        info.start = start;
        info.end = end;

        emit BatchUpdated(batchNumber, start, end);
    }
}


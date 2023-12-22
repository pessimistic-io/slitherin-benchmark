// SPDX-License-Identifier: SimPL-2.0
pragma solidity 0.8.17;

import "./ECDSA.sol";

library TransferHelper {
    function safeApprove(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: APPROVE_FAILED"
        );
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FAILED"
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FROM_FAILED"
        );
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract LITEAIRDROP {
    address public owner;
    address public signer;
    uint256 public totalOwnerReward;
    address public constant liteToken =
        0x691168C8dF23faeaB4dF89d823F3EA56BA5c3eBc;
    address public rewardToken;
    PoolInfo public pool;
    mapping(address => UserInfo) public userInfo;
    uint256 public rewardAmount = 1 ether;
    uint256 public constant rewardDay = 1 days;
    uint256 public constant maxPendingDay = 3 days;
    uint256 public airdropAmount = 1e12;

    bool public rewardStatus;
    uint256 public lastRewardDay;
    uint256 public totalReward;

    struct UserInfo {
        uint256 stakedOf;
        uint256 rewardOf;
        uint256 userReward;
        uint256 withdrawReward;
        uint256 lastUpdateAt;
    }

    struct PoolInfo {
        uint256 totalStaked;
        uint256 accPerShare;
    }

    constructor(address _signer) {
        signer = _signer;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "caller is not the owner");
        _;
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = _rewardToken;
    }

    function setRewardStatus(bool _rewardStatus) external onlyOwner {
        rewardStatus = _rewardStatus;
        if (rewardStatus) {
            lastRewardDay = block.timestamp / rewardDay;
        }
    }

    function setRewardAmount(uint256 _rewardAmount) external onlyOwner {
        rewardAmount = _rewardAmount;
    }

    function setAirdropAmount(uint256 _airdropAmount) external onlyOwner {
        airdropAmount = _airdropAmount;
    }

    function updatePool() external {
        require(rewardStatus, "not reward status");
        require(pool.totalStaked > 0, "not staked");
        require(
            block.timestamp / rewardDay > lastRewardDay,
            "last reward day not reached"
        );

        _updatePool();
    }

    function _updatePool() internal {
        if (
            rewardStatus &&
            pool.totalStaked > 0 &&
            block.timestamp / rewardDay > lastRewardDay
        ) {
            lastRewardDay = block.timestamp / rewardDay;
            pool.accPerShare += (rewardAmount * 1e12) / pool.totalStaked;
        }
    }

    function update(
        address _account,
        uint256 _stakeOf,
        uint256 _expiry,
        bytes memory _signature
    ) external {
        require(_expiry > block.timestamp, "invalid expiry");
        bytes32 _msgHash = getMessageHash(_account, _stakeOf, _expiry);
        bytes32 _ethSignedMessageHash = ECDSA.toEthSignedMessageHash(_msgHash);
        require(verify(_ethSignedMessageHash, _signature), "Invalid signature");

        _updatePool();
        UserInfo storage user = userInfo[msg.sender];
        if (user.stakedOf > 0) {
            _settlePendingToken(msg.sender);
        }

        if (user.lastUpdateAt == 0 && airdropAmount > 0) {
            uint256 balance = IERC20(liteToken).balanceOf(address(this));
            if (balance >= airdropAmount) {
                TransferHelper.safeTransfer(
                    liteToken,
                    msg.sender,
                    airdropAmount
                );
            }
        }

        user.lastUpdateAt = block.timestamp;
        if (_stakeOf != user.stakedOf) {
            pool.totalStaked = pool.totalStaked + _stakeOf - user.stakedOf;
            user.stakedOf = user.stakedOf + _stakeOf - user.stakedOf;
        }

        user.rewardOf = (user.stakedOf * pool.accPerShare) / 1e12;
    }

    function withdraw() external {
        require(rewardToken != address(0), "not reward token");
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.userReward - user.withdrawReward;
        require(amount > 0, "not enough reward");
        TransferHelper.safeTransfer(rewardToken, msg.sender, amount);
        user.withdrawReward = user.userReward;
    }

    function _settlePendingToken(address _user) internal {
        UserInfo storage user = userInfo[_user];
        uint256 pending = ((user.stakedOf * pool.accPerShare) / 1e12) -
            user.rewardOf;

        uint256 second = block.timestamp - user.lastUpdateAt;
        if (second >= maxPendingDay) {
            uint256 secondReward = pending / second;
            uint256 realPending = maxPendingDay * secondReward;
            totalOwnerReward += pending - realPending;
            pending = realPending;
        }

        user.userReward += pending;
    }

    function pendingToken(address _account) external view returns (uint256) {
        uint256 pending;
        UserInfo memory user = userInfo[_account];
        if (user.stakedOf > 0) {
            uint256 _accPerShare = pool.accPerShare;
            if (
                rewardStatus &&
                pool.totalStaked > 0 &&
                block.timestamp / rewardDay > lastRewardDay
            ) {
                _accPerShare += (rewardAmount * 1e12) / pool.totalStaked;
            }

            pending = ((user.stakedOf * _accPerShare) / 1e12) - user.rewardOf;
            uint256 second = block.timestamp - user.lastUpdateAt;
            if (second >= maxPendingDay) {
                uint256 secondReward = pending / second;
                uint256 realPending = maxPendingDay * secondReward;
                pending = realPending;
            }
        }

        return pending;
    }

    function settleOwnerToken(address to_) external onlyOwner {
        require(rewardToken != address(0), "not reward token");
        TransferHelper.safeTransfer(rewardToken, to_, totalOwnerReward);
        totalOwnerReward = 0;
    }

    function withdrawToken(
        address token_,
        address to_,
        uint256 amount_
    ) external onlyOwner {
        TransferHelper.safeTransfer(token_, to_, amount_);
    }

    function getMessageHash(
        address _account,
        uint256 _stakeOf,
        uint256 _expiry
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _stakeOf, _expiry));
    }

    function verify(
        bytes32 _msgHash,
        bytes memory _signature
    ) public view returns (bool) {
        return ECDSA.recover(_msgHash, _signature) == signer;
    }
}


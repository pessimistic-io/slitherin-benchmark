// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ECDSAUpgradeable.sol";

import "./IRewardTracker.sol";
import "./ImplementationGuard.sol";

contract Claimer is IRewardTracker, OwnableUpgradeable, ReentrancyGuardUpgradeable, ImplementationGuard {
    address public vester;
    address public muxToken;
    address public mcbToken;
    address public authetnicator;

    // id: 0
    uint256 public beginTime;
    uint256 public endTime;
    uint256 public totalClaimed;

    mapping(address => uint256) public claimed;

    struct RoundStat {
        uint256 beginTime;
        uint256 endTime;
        uint256 totalAmount;
        uint256 totalClaimed;
    }

    struct Round {
        uint256 beginTime;
        uint256 endTime;
        uint256 totalAmount;
        uint256 totalClaimed;
        mapping(address => uint256) claimed;
    }

    // id: [1-...]
    mapping(uint256 => Round) public rounds;

    mapping(address => uint256) public accumulativeRoundClaimed;

    event Claim(address recipient, uint256 amount);
    event ClaimRound(uint256 id, address recipient, uint256 amount);
    event Refund(uint256 id, uint256 amount);

    function initialize(
        address _vester,
        address _muxToken,
        address _mcbToken,
        uint256 _startTime,
        uint256 _endTime
    ) external initializer onlyDelegateCall {
        __Ownable_init();

        vester = _vester;
        muxToken = _muxToken;
        mcbToken = _mcbToken;
        beginTime = _startTime;
        endTime = _endTime;
    }

    function getRoundData(uint256 id) external view returns (RoundStat memory stat) {
        if (id == 0) {
            stat = RoundStat({
                beginTime: beginTime,
                endTime: endTime,
                totalAmount: 16366 * 1e18,
                totalClaimed: totalClaimed
            });
        } else {
            Round storage round = rounds[id];
            stat = RoundStat({
                beginTime: round.beginTime,
                endTime: round.endTime,
                totalAmount: round.totalAmount,
                totalClaimed: round.totalClaimed
            });
        }
    }

    function setAuthenticator(address _authenticator) external onlyOwner {
        authetnicator = _authenticator;
    }

    function setRoundData(uint256 id, uint256 _totalAmount, uint256 _beginTime, uint256 _endTime) external onlyOwner {
        require(id != 0, "CannotSetInitialRound");
        rounds[id].totalAmount = _totalAmount;
        rounds[id].beginTime = _beginTime;
        rounds[id].endTime = _endTime;
    }

    function setEndTime(uint256 id, uint256 _endTime) external onlyOwner {
        if (id == 0) {
            endTime = _endTime;
        } else {
            rounds[id].endTime = _endTime;
        }
    }

    function refund(uint256 id) external onlyOwner {
        uint256 refundBalance;
        if (id == 0) {
            require(block.timestamp >= endTime, "NotEnd");
            // patch for first round
            refundBalance = 16366 * 1e18 - totalClaimed;
        } else {
            Round storage round = rounds[id];
            require(block.timestamp >= round.endTime, "NotEnd");
            refundBalance = round.totalAmount - round.totalClaimed;
        }
        IERC20Upgradeable(mcbToken).transfer(msg.sender, refundBalance);
        emit Refund(id, refundBalance);
    }

    function hasClaimed(uint256 id, address account) external view returns (bool) {
        if (id == 0) {
            return claimed[account] > 0;
        } else {
            return rounds[id].claimed[account] > 0;
        }
    }

    function averageStakedAmounts(address) external pure override returns (uint256) {
        return 0;
    }

    function cumulativeRewards(address _account) external view override returns (uint256) {
        return claimed[_account] + accumulativeRoundClaimed[_account];
    }

    function claim(uint256 id, uint256 amount, bytes calldata signature) external nonReentrant {
        if (id == 0) {
            address recipient = msg.sender;
            require(block.timestamp >= beginTime, "NotBegin");
            require(block.timestamp < endTime, "AlreadyEnd");
            require(claimed[recipient] == 0, "AlreadyClaimed");

            claimed[recipient] = amount;
            totalClaimed += amount;

            bytes32 message = ECDSAUpgradeable.toEthSignedMessageHash(
                keccak256(abi.encodePacked(amount, recipient, address(this)))
            );
            address signer = ECDSAUpgradeable.recover(message, signature);
            require(signer == authetnicator, "InvalidSignature");

            IERC20Upgradeable(muxToken).transfer(recipient, amount);
            IERC20Upgradeable(mcbToken).transfer(vester, amount);

            emit Claim(recipient, amount);
        } else {
            address recipient = msg.sender;
            Round storage round = rounds[id];
            require(round.totalAmount != 0, "RoundNotSet");
            require(block.timestamp >= round.beginTime, "NotBegin");
            require(block.timestamp < round.endTime, "AlreadyEnd");
            require(round.claimed[recipient] == 0, "AlreadyClaimed");

            round.claimed[recipient] += amount;
            round.totalClaimed += amount;
            accumulativeRoundClaimed[recipient] += amount;

            bytes32 message = ECDSAUpgradeable.toEthSignedMessageHash(
                keccak256(abi.encodePacked(id, amount, recipient, address(this)))
            );
            address signer = ECDSAUpgradeable.recover(message, signature);
            require(signer == authetnicator, "InvalidSignature");

            IERC20Upgradeable(muxToken).transfer(recipient, amount);
            IERC20Upgradeable(mcbToken).transfer(vester, amount);

            emit ClaimRound(id, recipient, amount);
        }
    }
}


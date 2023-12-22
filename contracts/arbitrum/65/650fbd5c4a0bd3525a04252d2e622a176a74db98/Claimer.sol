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

    uint256 public beginTime;
    uint256 public endTime;
    uint256 public totalClaimed;

    mapping(address => uint256) public claimed;

    event Claim(address recipient, uint256 amount);

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

    function setEndTime(uint256 _endTime) external onlyOwner {
        endTime = _endTime;
    }

    function setAuthenticator(address _authenticator) external onlyOwner {
        authetnicator = _authenticator;
    }

    function refund() external onlyOwner {
        require(block.timestamp >= endTime, "NotEnd");
        // refund mcb
        uint256 mcbBalance = IERC20Upgradeable(mcbToken).balanceOf(address(this));
        IERC20Upgradeable(mcbToken).transfer(msg.sender, mcbBalance);
    }

    function averageStakedAmounts(address) external pure override returns (uint256) {
        return 0;
    }

    function cumulativeRewards(address _account) external view override returns (uint256) {
        return claimed[_account];
    }

    function claim(uint256 amount, bytes calldata signature) external nonReentrant {
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
    }
}


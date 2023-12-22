// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IRewardTracker.sol";
import "./ImplementationGuard.sol";

interface IMintable {
    function mint(address account, uint256 amount) external;
}

contract MuxSender is IRewardTracker, OwnableUpgradeable, ReentrancyGuardUpgradeable, ImplementationGuard {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Receipt {
        address recipient;
        uint256 amount;
    }

    address public vester;
    address public muxToken;
    address public mcbToken;

    uint256 public totalSent;
    mapping(address => uint256) public sent;

    event Send(address recipient, uint256 amount);

    function initialize(address _vester, address _muxToken, address _mcbToken) external initializer onlyDelegateCall {
        __Ownable_init();

        vester = _vester;
        muxToken = _muxToken;
        mcbToken = _mcbToken;
    }

    function averageStakedAmounts(address) external pure override returns (uint256) {
        return 0;
    }

    function cumulativeRewards(address _account) external view override returns (uint256) {
        return sent[_account];
    }

    function send(address recipient, uint256 amount) external nonReentrant {
        require(recipient != address(0), "InvalidRecipient");
        require(amount != 0, "InvalidAmount");

        sent[recipient] += amount;
        totalSent += amount;

        IMintable(muxToken).mint(recipient, amount);
        IERC20Upgradeable(mcbToken).transferFrom(msg.sender, vester, amount);

        emit Send(recipient, amount);
    }

    function batchSend(Receipt[] memory receipts) external nonReentrant {
        uint256 sum = 0;
        for (uint256 i = 0; i < receipts.length; i++) {
            Receipt memory receipt = receipts[i];
            if (receipt.recipient == address(0) || receipt.amount == 0) {
                continue;
            }
            IMintable(muxToken).mint(receipt.recipient, receipt.amount);
            sent[receipt.recipient] += receipt.amount;
            emit Send(receipt.recipient, receipt.amount);
            sum += receipt.amount;
        }
        totalSent += sum;
        IERC20Upgradeable(mcbToken).transferFrom(msg.sender, vester, sum);
    }
}


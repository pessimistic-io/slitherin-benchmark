// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ECDSAUpgradeable.sol";

import "./ImplementationGuard.sol";

contract TradingRebateDistributor is OwnableUpgradeable, ReentrancyGuardUpgradeable, ImplementationGuard {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public vault;
    address public rewardToken;
    address public authenticator;
    uint256 public totalClaimed;

    mapping(address => uint256) public cumulativeClaimed;
    mapping(address => bool) public maintainers;

    event Claim(address recipient, uint256 amount, uint256 cumulativeClaimed);

    function initialize(
        address _vault,
        address _rewardToken,
        address _authenticator
    ) external initializer onlyDelegateCall {
        __Ownable_init();

        vault = _vault;
        rewardToken = _rewardToken;
        authenticator = _authenticator;
    }

    function setAuthenticator(address _authenticator) external onlyOwner {
        authenticator = _authenticator;
    }

    function setMaintainers(address maintainer, bool enable) external onlyOwner {
        maintainers[maintainer] = enable;
    }

    function rescue() external nonReentrant {
        require(msg.sender == owner() || maintainers[msg.sender], "InvalidCaller");
        IERC20Upgradeable(rewardToken).safeTransfer(vault, IERC20Upgradeable(rewardToken).balanceOf(address(this)));
    }

    function claim(uint256 cumulativeAmount, bytes calldata signature) external nonReentrant {
        address recipient = msg.sender;
        require(cumulativeClaimed[recipient] < cumulativeAmount, "NoRewardToClaim");

        bytes32 message = ECDSAUpgradeable.toEthSignedMessageHash(
            keccak256(abi.encodePacked(block.chainid, cumulativeAmount, recipient, address(this)))
        );
        address signer = ECDSAUpgradeable.recover(message, signature);
        require(signer == authenticator, "InvalidSignature");

        uint256 amount = cumulativeAmount - cumulativeClaimed[recipient];
        cumulativeClaimed[recipient] = cumulativeAmount;
        totalClaimed += amount;

        IERC20Upgradeable(rewardToken).safeTransfer(recipient, amount);
        emit Claim(recipient, amount, cumulativeClaimed[recipient]);
    }
}


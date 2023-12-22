// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.4;

import "./SafeERC20.sol";
import "./Interfaces.sol";
import "./AccessControl.sol";

/**
 * @author Heisenberg
 * @title Buffer SettlementFeeDistributor
 * @notice Distributes the SettlementFee Collected by the Buffer Protocol
 */

contract SettlementFeeDistributorV2 is AccessControl {
    using SafeERC20 for ERC20;

    address[] public shareHolders;
    uint256[] public shareHolderPercentages;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    ERC20 public tokenX;

    event SetShareHolderDetails(
        address[] shareHolders,
        uint256[] shareHolderPercentages
    );

    constructor(ERC20 _tokenX) {
        tokenX = _tokenX;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // All percentages are with a factor of e2
    function setShareHolderDetails(
        address[] memory _shareHolders,
        uint256[] memory _shareHolderPercentages
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _shareHolders.length == _shareHolderPercentages.length,
            "Array length of shareholders and shareholder percents don't match"
        );
        uint256 totalShareHolderPercentage;
        for (uint256 n = 0; n < _shareHolderPercentages.length; n++) {
            totalShareHolderPercentage += _shareHolderPercentages[n];
        }
        require(
            totalShareHolderPercentage == 10000, // 100 with a factor of e2
            "Sum of shareholder percents should be equal to 100"
        );
        shareHolders = _shareHolders;
        shareHolderPercentages = _shareHolderPercentages;
        emit SetShareHolderDetails(shareHolders, shareHolderPercentages);
    }

    function distribute() external onlyRole(DISTRIBUTOR_ROLE) {
        uint256 contractBalance = tokenX.balanceOf(address(this));
        uint256 remainingBalance = contractBalance;
        for (uint256 n = 0; n < shareHolders.length; n++) {
            if (n == (shareHolders.length) - 1) {
                tokenX.safeTransfer(shareHolders[n], remainingBalance);
            } else {
                uint256 amount = (contractBalance * shareHolderPercentages[n]) /
                    10000;
                tokenX.safeTransfer(shareHolders[n], amount);
                remainingBalance -= amount;
            }
        }
    }

    // Emergency function to withdraw any token stuck in the contract
    function withdrawTokenX(
        ERC20 _tokenX,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _tokenX.safeTransfer(msg.sender, _amount);
    }
}


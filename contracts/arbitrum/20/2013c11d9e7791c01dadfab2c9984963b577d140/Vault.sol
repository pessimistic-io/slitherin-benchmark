// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";

import "./SyntheX.sol";

/**
 * @title FeeVault
 * @notice FeeVault contract to store fees from the protocol
 * @custom:security-contact prasad@chainscore.finance
 */
contract Vault is UUPSUpgradeable {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    // AddressStorage contract
    SyntheX public synthex;

    fallback() external payable {}

    receive() external payable {}

    function initialize(address _synthex) external initializer {
        __UUPSUpgradeable_init();

        synthex = SyntheX(_synthex);
    }

    /// @dev UUPS upgradeable proxy
    function _authorizeUpgrade(address) internal override onlyL1Admin {}


    modifier onlyL1Admin() {
        require(synthex.isL1Admin(msg.sender), Errors.CALLER_NOT_L1_ADMIN);
        _;
    }

    /**
     * @dev Withdraw tokens from the vault
     * @param _tokenAddress Token address
     * @param amount Amount to withdraw
     * @notice Only L1_ADMIN can withdraw
     */
    function withdraw(address _tokenAddress, uint256 amount)
        external onlyL1Admin
    {
        ERC20Upgradeable(_tokenAddress).safeTransfer(msg.sender, amount);
    }

    function withdrawETH(uint256 amount)
        external onlyL1Admin
    {
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, Errors.TRANSFER_FAILED);
    }
}

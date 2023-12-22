// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./IPlennyERC20.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyRewardStorage.sol";

/// @title  PlennyReward
/// @notice Stores token reserved for rewards given for locking Plenny into the DAO Governance module as well as for
///         locking LP-token into the liquidity mining contract.
contract PlennyReward is PlennyBasePausableV2, PlennyRewardStorage {

    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IPlennyERC20;

    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;

    /// @notice Initializes the smart contract instead of a constructor. Called once during deployment.
    /// @param  _registry Plenny contract registry
    function initialize(address _registry) external initializer {
        PlennyBasePausableV2.__plennyBasePausableInit(_registry);
    }

    /// @notice Transfers the reward to the given address.
    /// @param  to address
    /// @param  amount reward amount
    /// @return bool action
    function transfer(address to, uint256 amount) external override whenNotPaused returns (bool) {
        _logs_();
        _onlyAuth();

        IPlennyERC20 token = contractRegistry.plennyTokenContract();
        token.safeTransfer(to, amount);
        return true;
    }

    /// @dev    logs the function calls.
    function _logs_() internal {
        emit LogCall(msg.sig, msg.sender, msg.data);
    }

    /// @dev    Only the authorized contracts can withdraw the reward.
    function _onlyAuth() internal view {
        require(contractRegistry.getAddress("PlennyLiqMining") == msg.sender ||
            contractRegistry.getAddress("PlennyLocking") == msg.sender, "ERR_NOT_AUTH");
    }
}


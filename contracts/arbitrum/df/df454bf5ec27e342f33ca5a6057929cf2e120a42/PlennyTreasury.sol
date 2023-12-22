// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./IUniswapV2Pair.sol";
import "./IPlennyERC20.sol";
import "./IWETH.sol";
import "./PlennyBasePausableV2.sol";
import "./PlennyTreasuryStorage.sol";

/// @title  PlennyTreasury
/// @notice Stores Plenny reserved for rewards given within the capacity market and for oracle validations.
contract PlennyTreasury is PlennyBasePausableV2, PlennyTreasuryStorage {

    using SafeERC20Upgradeable for IPlennyERC20;

    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;

    /// @dev    logs the function calls.
    modifier _logs_() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    /// @dev    If a token is supported in the treasury.
    modifier onlySupported(address tokenToTransfer) {
        require(isSupported(tokenToTransfer), "ERR_NOT_SUPPORTED");
        _;
    }

    /// @notice Initializes the smart contract instead of an constructor. Called once during deploy.
    /// @param  _registry Plenny contract registry
    function initialize(address _registry) external initializer {
        PlennyBasePausableV2.__plennyBasePausableInit(_registry);
    }

    /// @notice Transfers the amount of the given token to the given address. Called by the owner.
    /// @param  to address
    /// @param  tokenToTransfer token address
    /// @param  value reward amount
    function transfer(address to, address tokenToTransfer, uint256 value)
    external onlyOwner whenNotPaused onlySupported(tokenToTransfer) _logs_ {

        require(IPlennyERC20(tokenToTransfer).balanceOf(address(this)) >= value, "ERR_NO_FUNDS");
        IPlennyERC20(tokenToTransfer).safeTransfer(to, value);
    }

    /// @notice Approves a reward for the given address.
    /// @param  addr address to send reward to
    /// @param  amount reward amount
    /// @return bool true/false
    function approve(address addr, uint256 amount) external override returns (bool) {
        _onlyAuth();
        contractRegistry.plennyTokenContract().safeApprove(addr, amount);
        return true;
    }

    /// @notice If token is supported by the treasury.
    /// @param  tokenToTransfer token address
    /// @return bool true/false
    function isSupported(address tokenToTransfer) public view returns (bool) {
        return contractRegistry.requireAndGetAddress("PlennyERC20") == tokenToTransfer
        || contractRegistry.requireAndGetAddress("UNIETH-PL2") == tokenToTransfer;
    }

    /// @dev    Only the authorized contracts can make requests.
    function _onlyAuth() internal view {
        require(contractRegistry.getAddress("PlennyLiqMining") == msg.sender
        || contractRegistry.requireAndGetAddress("PlennyOracleValidator") == msg.sender
        || contractRegistry.requireAndGetAddress("PlennyCoordinator") == msg.sender
            || contractRegistry.requireAndGetAddress("PlennyValidatorElection") == msg.sender, "ERR_NOT_AUTH");
    }
}


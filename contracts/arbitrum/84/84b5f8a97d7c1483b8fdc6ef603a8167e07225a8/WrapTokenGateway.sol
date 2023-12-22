// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./Ownable2StepUpgradeable.sol";
import "./Errors.sol";
import "./IYieldStrategyManager.sol";
import "./ISavvyPositionManager.sol";
import "./IWAVAX9.sol";
import "./IWrapTokenGateway.sol";
import "./IAllowlist.sol";
import "./ISavvyRedlist.sol";
import "./TokenUtils.sol";
import "./Checker.sol";

/// @title  WAVAXGateway
/// @author Savvy DeFi
contract WrapTokenGateway is IWrapTokenGateway, Ownable2StepUpgradeable {
    /// @notice The version.
    string public constant version = "1.0.0";

    /// @notice The wrapped ethereum contract.
    IWAVAX9 public WAVAX;

    /// @notice The address of the allowlist contract.
    address public allowlist;

    /// @notice The address of the SavvyRedlist contract.
    address public savvyRedlist;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _wavax,
        address _allowlist,
        address _savvyRedlist
    ) public initializer {
        WAVAX = IWAVAX9(_wavax);
        allowlist = _allowlist;
        savvyRedlist = _savvyRedlist;
        __Ownable_init();
    }

    /// @dev Allows for payments from the WAVAX contract.
    receive() external payable {
        require(IWAVAX9(msg.sender) == WAVAX, "Unauthorized WAVAX");
    }

    /// @inheritdoc IWrapTokenGateway
    function refreshAllowance(
        address _savvyPositionManager
    ) external onlyOwner {
        require(
            ISavvyPositionManager(_savvyPositionManager).supportInterface(
                type(ISavvyAdminActions).interfaceId
            ),
            "not SavvyPositionManager address"
        );
        WAVAX.approve(_savvyPositionManager, type(uint256).max);
    }

    /// @inheritdoc IWrapTokenGateway
    function removeAllowance(address _savvyPositionManager) external onlyOwner {
        require(
            ISavvyPositionManager(_savvyPositionManager).supportInterface(
                type(ISavvyAdminActions).interfaceId
            ),
            "not SavvyPositionManager address"
        );
        WAVAX.approve(_savvyPositionManager, 0);
    }

    /// @inheritdoc IWrapTokenGateway
    function depositBaseToken(
        address _savvyPositionManager,
        address _yieldToken,
        uint256 _amount,
        address _recipient,
        uint256 _minimumAmountOut
    ) external payable override {
        _onlyAllowlisted();
        _onlyRedlisted(_savvyPositionManager);
        Checker.checkArgument(
            _amount == msg.value,
            "unmatched deposit token amount"
        );
        WAVAX.deposit{value: msg.value}();
        TokenUtils.safeApprove(address(WAVAX), _savvyPositionManager, _amount);
        ISavvyPositionManager(_savvyPositionManager).depositBaseToken(
            _yieldToken,
            _amount,
            _recipient,
            _minimumAmountOut
        );
    }

    /// @inheritdoc IWrapTokenGateway
    function withdrawBaseToken(
        address _savvyPositionManager,
        address _yieldToken,
        uint256 _shares,
        address _recipient,
        uint256 _minimumAmountOut
    ) external {
        _onlyAllowlisted();
        // Ensure that the underlying of the target yield token is in fact WAVAX
        IYieldStrategyManager yieldStrategyManager = ISavvyPositionManager(
            _savvyPositionManager
        ).yieldStrategyManager();
        ISavvyPositionManager.YieldTokenParams
            memory params = yieldStrategyManager.getYieldTokenParameters(
                _yieldToken
            );
        Checker.checkArgument(
            params.baseToken == address(WAVAX),
            "invalid token address"
        );

        uint256 amount = ISavvyPositionManager(_savvyPositionManager)
            .withdrawBaseTokenFrom(
                msg.sender,
                _yieldToken,
                _shares,
                address(this),
                _minimumAmountOut
            );
        _convertWAVAX();

        (bool success, ) = _recipient.call{value: amount}(new bytes(0));
        Checker.checkState(success, "withdraw failed");
    }

    /// @inheritdoc IWrapTokenGateway
    function repayWithBaseToken(
        address _savvyPositionManager,
        address _recipient,
        uint256 _amount
    ) external payable returns (uint256) {
        _onlyAllowlisted();
        Checker.checkArgument(
            _amount == msg.value,
            "unmatched deposit token amount"
        );
        WAVAX.deposit{value: msg.value}();
        TokenUtils.safeApprove(address(WAVAX), _savvyPositionManager, _amount);
        return
            ISavvyPositionManager(_savvyPositionManager).repayWithBaseToken(
                address(WAVAX),
                _amount,
                _recipient
            );
    }

    /// @dev Checks the allowlist for msg.sender.
    ///
    /// Reverts if msg.sender is not in the allowlist.
    function _onlyAllowlisted() internal view {
        // Check if the message sender is an EOA. In the future, this potentially may break. It is important that functions
        // which rely on the allowlist not be explicitly vulnerable in the situation where this no longer holds true.
        // Only check the allowlist for calls from contracts.
        address sender = msg.sender;
        require(
            tx.origin == sender || IAllowlist(allowlist).isAllowed(msg.sender),
            "Unauthorized allowlist"
        );
    }

    /// @dev Checks that the `msg.sender` is redlisted.
    ///
    /// @dev `msg.sender` must be redlisted or this call will revert with an {Unauthorized} error.
    ///
    /// @dev This function is not view because it updates the cache.
    function _onlyRedlisted(address _savvyPositionManager) internal {
        bool redlistActive = ISavvyPositionManager(_savvyPositionManager)
            .redlistActive();
        bool protocolTokenRequired = ISavvyPositionManager(
            _savvyPositionManager
        ).protocolTokenRequired();
        require(
            (!redlistActive && !protocolTokenRequired) ||
                ISavvyRedlist(savvyRedlist).isRedlisted(
                    msg.sender,
                    redlistActive,
                    protocolTokenRequired
                ),
            "Unauthorized redlist"
        );
    }

    /// @notice Convert all WAVAX to AVAX
    function _convertWAVAX() internal {
        uint256 amount = WAVAX.balanceOf(address(this));
        WAVAX.withdraw(amount);
    }

    uint256[100] private __gap;
}


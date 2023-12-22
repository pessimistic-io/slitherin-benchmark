// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";
import {IOneInchV4Swapper} from "./IOneInchV4Swapper.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";

contract MultichainRewards is AccessControlUpgradeable {
    IOneInchV4Swapper public swapper;
    address public swapsReceiver;

    bytes32 private constant KEEPER = keccak256("KEEPER");

    struct OneInchSwap {
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 minAmountOut;
        bytes externalData;
    }

    function initialize(address _swapper, address _keeper, address _swapsReceiver) external initializer {
        __AccessControl_init();

        if (_swapper == address(0) || _keeper == address(0) || _swapsReceiver == address(0)) {
            revert ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KEEPER, _keeper);

        swapsReceiver = _swapsReceiver;
        swapper = IOneInchV4Swapper(_swapper);
    }

    /// @notice Swap and Bridge ERC20 trough Socket middleware.
    /// @dev https://docs.socket.tech/socket-api/v2/guides/socket-smart-contract-integration
    /// @param _to The Socket contract address where transaction has to be sent.
    /// @param _txData The raw data that should be sent to the contract for making a transaction. Includes the encoded function signature and params.
    /// @param _token Address of the token that needs to be given approval.
    /// @param _allowanceTarget The Socket contract that needs approval in order to transfer user tokens.
    function bridgingBribes(
        address payable _to,
        bytes calldata _txData,
        IERC20 _token,
        uint256 _amount,
        address _allowanceTarget
    ) external {
        _onlyKeeper();

        uint256 allowance = _token.allowance(address(this), _allowanceTarget);

        if (allowance < _amount) {
            _token.approve(_allowanceTarget, _amount - allowance);
        }

        (bool success,) = _to.call(_txData);

        if (!success) {
            revert BridgeFail();
        }

        emit BridgingBribes(msg.sender, _to, _txData, address(_token), _allowanceTarget, _amount);
    }

    /// @notice Changes allowances.
    /// @dev Can be used to save gas, max approving trustful contracts.
    /// @param _tokens The tokens that will have their allowances changed.
    /// @param _amounts New allowances.
    /// @param _allowanceTarget address that will have the allowance change
    function editAllowance(IERC20[] calldata _tokens, uint256[] calldata _amounts, address[] calldata _allowanceTarget)
        external
    {
        _onlyGovernor();

        uint256 length = _tokens.length;

        if (length != _amounts.length || length == 0) {
            revert Different();
        }

        for (uint8 i = 0; i < length;) {
            _tokens[i].approve(_allowanceTarget[i], _amounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Swap and Bridge ERC20 trough Socket middleware.
    /// @dev https://docs.socket.tech/socket-api/v2/guides/socket-smart-contract-integration
    /// @param _to The Socket contract address where transaction has to be sent.
    /// @param _txData The raw data that should be sent to the contract for making a transaction. Includes the encoded function signature and params.
    /// @param _amount Amount of ETH.
    function bridgeNativeEth(address payable _to, bytes memory _txData, uint256 _amount) public payable {
        _onlyKeeper();

        (bool success,) = _to.call{value: _amount}(_txData);
        if (!success) {
            revert BridgeFail();
        }

        emit BridgingETH(msg.sender, _to, _txData, _amount);
    }

    /// @notice Swaps bribes tokens.
    /// @dev Uses 1inch api to generate the data.
    /// @param _swapParams Array of the data containing the swaps.
    function swap(OneInchSwap[] memory _swapParams) external {
        _onlyKeeper();

        uint256 length = _swapParams.length;
        uint8 i = 0;

        for (; i < length;) {
            IERC20 token = IERC20(_swapParams[i].tokenIn);
            uint256 amount = _swapParams[i].amountIn;

            uint256 allowance = token.allowance(address(this), address(swapper));

            if (allowance < amount) {
                token.approve(address(swapper), amount - allowance);
            }

            swapper.swap(
                _swapParams[i].tokenIn,
                _swapParams[i].amountIn,
                _swapParams[i].tokenOut,
                _swapParams[i].minAmountOut,
                _swapParams[i].externalData
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Transfers ERC-20 tokens out of this contract.
    /// @dev This function is OnlyGovernor.
    /// @param _tokens Tokens that will be transferred out.
    /// @param _amounts Amounts of _tokens that will be transferred out
    function emergencyTransfer(IERC20[] calldata _tokens, uint256[] calldata _amounts, address _to) external {
        _onlyGovernor();

        uint256 length = _tokens.length;

        if (length != _amounts.length || length == 0) {
            revert Different();
        }

        for (uint8 i = 0; i < length;) {
            _tokens[i].transfer(_to, _amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Transfers native ETH out.
    /// @dev This function is OnlyGovernor.
    /// @param _amount Amount of native ETH that will be transferred
    function emergencyTransferNative(uint256 _amount, address _to) external {
        _onlyGovernor();

        (bool success,) = _to.call{value: _amount}("");
        if (!success) {
            revert CallFailed();
        }
    }

    /// @notice Adds a keeper (bot) granting him the KEEPER role.
    /// @dev This function is OnlyGovernor.
    /// @param _keeper Address of new keeper.
    function addKeeper(address _keeper) external {
        _onlyGovernor();

        if (_keeper == address(0)) {
            revert ZeroAddress();
        }

        _grantRole(KEEPER, _keeper);
    }

    /// @notice Updates the address that receives swaps outputs.
    /// @dev For reducing Keeper trust, we only transfer swaps to the swapsReceiver.
    /// @param _receiver Address that will be the swapsReceiver.
    function updateSwapsReceiver(address _receiver) external {
        _onlyGovernor();

        if (_receiver == address(0)) {
            revert ZeroAddress();
        }

        swapsReceiver = _receiver;
    }

    function _onlyGovernor() private view {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert OnlyGov();
        }
    }

    function _onlyKeeper() private view {
        if (!hasRole(KEEPER, msg.sender)) {
            revert OnlyKeeper();
        }
    }

    event BridgingBribes(
        address caller,
        address indexed to,
        bytes txData,
        address indexed token,
        address indexed allowanceTarget,
        uint256 amount
    );

    event BridgingETH(address caller, address indexed to, bytes txData, uint256 amount);

    event TransferNative(address indexed to, uint256 amount);

    error OnlyGov();
    error OnlyKeeper();
    error BridgeFail();
    error CallFailed();
    error Different();
    error InvalidReceiver();
    error ZeroAddress();

    fallback() external payable {}
}


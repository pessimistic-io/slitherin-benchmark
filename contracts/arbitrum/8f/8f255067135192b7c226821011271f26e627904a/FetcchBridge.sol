//   _____    _           _       ____       _     _
//  |  ___|__| |_ ___ ___| |__   | __ ) _ __(_) __| | __ _  ___
//  | |_ / _ \ __/ __/ __| '_ \  |  _ \| '__| |/ _` |/ _` |/ _ \
//  |  _|  __/ || (_| (__| | | | | |_) | |  | | (_| | (_| |  __/
//  |_|  \___|\__\___\___|_| |_| |____/|_|  |_|\__,_|\__, |\___|
//                                                   |___/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import "./AccessControl.sol";
import {SafeERC20} from "./SafeERC20.sol";
import "./CommLayerAggregator.sol";
import "./UniV3Provider.sol";
import "./ITokenMessenger.sol";

interface IWrappedToken {
    function withdraw(uint256 amount) external;
}

contract FetcchBridge is AccessControl {
    using SafeERC20 for IERC20;

    /// @notice CommunicationLayerAggregator address
    CommLayerAggregator public commLayerAggregator;

    IERC20 public usdc;

    ITokenMessenger public tokenMessenger;

    UniV3Provider public uniV3;

    bytes32 public constant COMMLAYER = keccak256("COMMLAYER");

    address private constant NATIVE_TOKEN_ADDRESS =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    mapping(uint32 => address) private destination;

    constructor(address usdc_, address tokenMessenger_, address uniV3_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        usdc = IERC20(usdc_);
        tokenMessenger = ITokenMessenger(tokenMessenger_);
        uniV3 = UniV3Provider(uniV3_);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        address receiver,
        uint256 amount,
        uint256 commLayerId,
        uint32 destinationChain,
        bytes calldata extraParams
    ) external payable {
        uint256 amountOut;
        if (tokenIn == address(usdc)) {
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);
            amountOut = amount;
        } else {
            if (tokenIn == NATIVE_TOKEN_ADDRESS) {
                amountOut = uniV3.swapNative{value: amount}(address(usdc));
            } else {
                IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);
                IERC20(tokenIn).approve(address(uniV3), amount);
                amountOut = uniV3.swapERC20(
                    address(this),
                    tokenIn,
                    address(usdc),
                    amount
                );
            }
        }

        bytes memory payload = abi.encode(tokenOut, amountOut, receiver);

        uint256 gasValue = tokenIn == NATIVE_TOKEN_ADDRESS
            ? msg.value - amount
            : msg.value;
        commLayerAggregator.sendMsg{value: gasValue}(
            commLayerId,
            payload,
            extraParams
        );

        usdc.approve(address(tokenMessenger), amountOut);
        tokenMessenger.depositForBurn(
            amountOut,
            destinationChain,
            bytes32(uint256(uint160(destination[destinationChain]))),
            address(usdc)
        );
    }

    function release(
        address tokenOut,
        uint256 amount,
        address receiver
    ) external onlyRole(COMMLAYER) {
        if (tokenOut == address(usdc)) {
            usdc.safeTransfer(receiver, amount);
        } else if (tokenOut == NATIVE_TOKEN_ADDRESS) {
            usdc.approve(address(uniV3), amount);
            uint amountOut = uniV3.swapERC20(
                address(this),
                address(usdc),
                uniV3.wrappedNative(),
                amount
            );
            IERC20(uniV3.wrappedNative()).approve(
                uniV3.wrappedNative(),
                amountOut
            );
            IWrappedToken(uniV3.wrappedNative()).withdraw(amountOut);
            (bool success, ) = payable(receiver).call{value: amountOut}("");
            require(success);
        } else {
            usdc.approve(address(uniV3), amount);
            uniV3.swapERC20(receiver, address(usdc), tokenOut, amount);
        }
    }

    function registerCommLayers(
        address _commLayer
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(COMMLAYER, _commLayer);
    }

    function registerDestination(
        uint32 destinationChain,
        address destinationAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        destination[destinationChain] = destinationAddress;
    }

    /// @notice This function is responsible for chaning communication layer aggregator address
    /// @dev onlyOwner is allowed to call this function
    /// @param _newCommLayerAggregator Communication layer aggregator address
    function changeCommLayerAggregator(
        address _newCommLayerAggregator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        commLayerAggregator = CommLayerAggregator(_newCommLayerAggregator);
    }

    receive() external payable {}
}


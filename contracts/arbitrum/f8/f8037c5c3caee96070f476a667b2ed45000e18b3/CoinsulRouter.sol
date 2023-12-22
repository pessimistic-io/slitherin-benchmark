// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;
import "./Math.sol";
import "./SafeMath.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./StrayCollector.sol";

import "./console.sol";

interface CoinsulConnectors {
    function deposit(
        address additionalConnectorAddress,
        address[] memory depositTokens,
        uint256[] memory depositTokenAmounts,
        bytes[] memory connectorData,
        address userAddress
    ) external payable;

    function withdraw(
        address additionalConnectorAddress,
        address[] memory withdrawToken,
        uint256[] memory withdrawalAmount,
        bytes[] memory connectorData,
        address userAddress
    ) external payable;
}

interface SwapProxy {
    function swap(
        bytes memory _data,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 minReturn,
        address userAddress
    ) external payable returns (uint256);
}

contract CoinsulRouter is Ownable, StrayCollector {
    // libraries
    using SafeMath for uint256;

    // structs
    struct withdrawData {
        string withdrawConnectorName;
        address additionalConnectorAddress;
        address[] withdrawTokens; // if vault token is being held, always put in 0 index
        uint256[] withdrawTokenAmounts;
        bytes[] withdrawConnectorData;
    }

    struct swapData {
        bytes swapCallData;
        address originalToken;
        uint256 originalTokenAmount;
        address finalToken;
        uint256 minReturn; // should be the absolute minimum allowed to be returned (including slippage and price impact)
        uint256 returnToSenderFraction; // if requested, sends specific amount back to sender
    }

    struct depositData {
        string depositConnectorName;
        address additionalConnectorAddress;
        address[] depositTokens;
        uint256[] depositTokenFractions; // these are fractions
        uint256[] newDepositAmount;
        bytes[] depositConnectorData;
    }
    // events
    event AddedConnector(
        string indexed connectorName,
        address indexed connectorAddress
    );

    event UpdatedConnectorAddress(
        string indexed connectorName,
        address indexed oldAddress,
        address indexed newAddress
    );

    event Deposit(
        string indexed connectorName,
        address indexed userAddress,
        depositData data
    );

    event Withdraw(
        string indexed connectorName,
        address indexed userAddress,
        withdrawData data
    );

    event RouterSwap(
        address indexed userAddress,
        uint256 returnAmount,
        swapData data
    );

    // data
    mapping(string => address) public deployedConnectors;
    string[] public connectorNames;
    address public swapproxyAddress;
    uint256 MAX_INT = 2**256 - 1;

    constructor(address swapAddress) {
        swapproxyAddress = swapAddress;
    }

    function moveFunds(
        withdrawData[] memory withdrawArray,
        swapData[] calldata swapArray,
        depositData[] memory depositArray
    ) external payable {
        // make easily accessed Data objects
        withdrawData memory withdraw_data;
        swapData calldata swap_data;
        depositData memory deposit_data;

        // first perform necessary withdraws
        for (uint i = 0; i < withdrawArray.length; i++) {
            withdraw_data = withdrawArray[i];

            // if the connector has not been approved, approve it for maximum
            if (
                IERC20(withdraw_data.withdrawTokens[0]).allowance(
                    address(this),
                    deployedConnectors[withdraw_data.withdrawConnectorName]
                ) == 0
            ) {
                IERC20(withdraw_data.withdrawTokens[0]).approve(
                    deployedConnectors[withdraw_data.withdrawConnectorName],
                    MAX_INT
                );
            }
            // transfer vault tokens to here, user balance will also be confirmed by the connector
            IERC20(withdraw_data.withdrawTokens[0]).transferFrom(
                msg.sender,
                address(this),
                withdraw_data.withdrawTokenAmounts[0]
            );

            CoinsulConnectors(
                deployedConnectors[withdraw_data.withdrawConnectorName]
            ).withdraw(
                    withdraw_data.additionalConnectorAddress,
                    withdraw_data.withdrawTokens,
                    withdraw_data.withdrawTokenAmounts,
                    withdraw_data.withdrawConnectorData,
                    msg.sender
                );
            emit Withdraw(
                withdraw_data.withdrawConnectorName,
                msg.sender,
                withdraw_data
            );
        } // i withdraw loop

        // now perform any needed swaps
        for (uint i = 0; i < swapArray.length; i++) {
            swap_data = swapArray[i];
            uint256 returnAmount = 0;

            //if originalToken == finalToken, simply transfer the tokens to this contract.  otherwise, perform the needed swap
            if (swap_data.originalToken == swap_data.finalToken) {
                // transfer tokens to the router
                IERC20(swap_data.originalToken).transferFrom(
                    msg.sender,
                    address(this),
                    swap_data.originalTokenAmount
                );
            } else {
                // transfer tokens to the router
                IERC20(swap_data.originalToken).transferFrom(
                    msg.sender,
                    address(this),
                    swap_data.originalTokenAmount
                );

                //check for swap proxy approval
                if (
                    IERC20(swap_data.originalToken).allowance(
                        address(this),
                        swapproxyAddress
                    ) == 0
                ) {
                    IERC20(swap_data.originalToken).approve(
                        swapproxyAddress,
                        MAX_INT
                    );
                }

                //make the swaps.  the SwapProxy will always return the tokens to the msg.sender (here)
                (returnAmount) = SwapProxy(swapproxyAddress).swap(
                    swap_data.swapCallData,
                    swap_data.originalToken,
                    swap_data.originalTokenAmount,
                    swap_data.finalToken,
                    swap_data.minReturn,
                    address(this)
                );
                emit RouterSwap(msg.sender, returnAmount, swap_data);
            }

            if (swap_data.returnToSenderFraction > 0) {
                IERC20(swap_data.finalToken).transfer(
                    msg.sender,
                    returnAmount.mul(swap_data.returnToSenderFraction).div(
                        10000
                    )
                );
            }
        } // i swap loop

        // perform all requested deposits
        // internal for loop is to transfer all the requested tokens to the deposit connector
        for (uint i = 0; i < depositArray.length; i++) {
            deposit_data = depositArray[i];

            // define the amounts array to send to deposit connectors
            uint256[] memory depositTokenAmounts = new uint256[](
                deposit_data.depositTokens.length
            );

            // transfer each of the deposit tokens to the appropriate connector before calling deposit
            for (uint j = 0; j < deposit_data.depositTokens.length; j++) {
                // if the connector has not been approved, approve it for maximum
                if (
                    IERC20(deposit_data.depositTokens[j]).allowance(
                        address(this),
                        deployedConnectors[deposit_data.depositConnectorName]
                    ) == 0
                ) {
                    IERC20(deposit_data.depositTokens[j]).approve(
                        deployedConnectors[deposit_data.depositConnectorName],
                        MAX_INT
                    );
                }

                // initialize depositTokenAmounts to reflect current balance from previous withdrawals/swaps
                depositTokenAmounts[j] = IERC20(deposit_data.depositTokens[j])
                    .balanceOf(address(this));

                if (deposit_data.newDepositAmount[j] > 0) {
                    // tranfer the new tokens from msg.sender if it is a new deposit
                    IERC20(deposit_data.depositTokens[j]).transferFrom(
                        msg.sender,
                        address(this),
                        deposit_data.newDepositAmount[j]
                    );
                    // save the new token quantity
                    depositTokenAmounts[j] += deposit_data.newDepositAmount[j];
                }

                // use deposit fractions to determine final token amount to send to each connector
                depositTokenAmounts[j] = depositTokenAmounts[j]
                    .mul(deposit_data.depositTokenFractions[j])
                    .div(10000);
            }

            // make the deposit, the connector will return the vault tokens directly to the user wallet
            CoinsulConnectors(
                deployedConnectors[deposit_data.depositConnectorName]
            ).deposit(
                    deposit_data.additionalConnectorAddress,
                    deposit_data.depositTokens,
                    depositTokenAmounts,
                    deposit_data.depositConnectorData,
                    msg.sender
                );

            emit Deposit(
                deposit_data.depositConnectorName,
                msg.sender,
                deposit_data
            );
        } // i deposit loop

        // this loop just checks for any leftover tokens and returns them to user, in case a front-end mistake was made.
        // TODO:  need to come up with test cases that exercise this block
        for (uint i = 0; i < depositArray.length; i++) {
            deposit_data = depositArray[i];
            // in case the deposit data sent was incorrect, return all left-over tokens to user
            for (uint j = 0; j < deposit_data.depositTokens.length; j++) {
                if (
                    IERC20(deposit_data.depositTokens[j]).balanceOf(
                        address(this)
                    ) > 0
                ) {
                    IERC20(deposit_data.depositTokens[j]).transfer(
                        msg.sender,
                        IERC20(deposit_data.depositTokens[j]).balanceOf(
                            address(this)
                        )
                    );
                }
            }
        } // end of return funds loop
    } // end of moveFunds()

    function addConnector(string memory connectorName, address connectorAddress)
        external
        onlyOwner
    {
        address current = deployedConnectors[connectorName];
        deployedConnectors[connectorName] = connectorAddress;
        if (current == address(0x0)) {
            // don't have this one yet
            connectorNames.push(connectorName);
            emit AddedConnector(connectorName, connectorAddress);
        } else {
            // already have this one
            emit UpdatedConnectorAddress(
                connectorName,
                current,
                connectorAddress
            );
        }
    }

    function getConnectorAddress(string memory connectorName)
        external
        view
        returns (address)
    {
        return deployedConnectors[connectorName];
    }

    function nConnectors() external view returns (uint256) {
        return connectorNames.length;
    }
}


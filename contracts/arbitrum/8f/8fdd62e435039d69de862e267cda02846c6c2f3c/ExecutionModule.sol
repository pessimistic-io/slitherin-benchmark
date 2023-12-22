pragma solidity >=0.8.19;

import "./IExecutionModule.sol";
import "./Commands.sol";
import "./Dispatcher.sol";

/**
 * @title Execution Module is responsible for executing encoded commands along with provided inputs
 * @dev See IExecutionModule.
 */
contract ExecutionModule is IExecutionModule {
    // todo: add initialize method to set the immutables

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert TransactionDeadlinePassed();
        _;
    }

    /// @inheritdoc IExecutionModule
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline)
        external
        payable
        override
        checkDeadline(deadline)
        returns (bytes[] memory outputs)
    {
        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();
        outputs = new bytes[](numCommands);

        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex = 0; commandIndex < numCommands;) {
            bytes1 command = commands[commandIndex];

            bytes calldata input = inputs[commandIndex];

            bytes memory output = Dispatcher.dispatch(command, input);
            outputs[commandIndex] = output;

            unchecked {
                commandIndex++;
            }
        }
    }
}


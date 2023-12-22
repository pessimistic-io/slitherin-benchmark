// https://github.com/Uniswap/v3-periphery
pragma solidity 0.8.17;

// https://github.com/Uniswap/v3-periphery/blob/7431d30d8007049a4c9a3027c2e082464cd977e9/contracts/interfaces/IMulticall.sol
interface IMulticall {
    /// @notice Call multiple functions in the current contract and return the data from all of them if they all succeed
    /// @dev The `msg.value` should not be trusted for any method callable from multicall.
    /// @param data The encoded function data for each of the calls to make to this contract
    /// @return results The results from each of the calls passed in via data
    function multicall(
        bytes[] calldata data
    ) external payable returns (bytes[] memory results);
}


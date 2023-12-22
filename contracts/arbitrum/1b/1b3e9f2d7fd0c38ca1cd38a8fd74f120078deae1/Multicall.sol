// https://github.com/Uniswap/v3-periphery
pragma solidity 0.8.17;

import "./IMulticall.sol";

// https://github.com/Uniswap/v3-periphery/blob/1d69caf0d6c8cfeae9acd1f34ead30018d6e6400/contracts/base/Multicall.sol
abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(
        bytes[] calldata data
    ) public payable override returns (bytes[] memory results) {
        uint n = data.length;
        results = new bytes[](n);
        for (uint256 i = 0; i < n; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(
                data[i]
            );

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}


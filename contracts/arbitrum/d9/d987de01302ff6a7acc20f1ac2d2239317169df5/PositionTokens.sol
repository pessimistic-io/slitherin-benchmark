// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.18;

import "./Bytes.sol";
import "./String.sol";
import "./OverflowMath.sol";
import "./IPositionERC1155.sol";
import "./IRangePoolFactory.sol";
import "./RangePoolStructs.sol";
import "./ERC20.sol";

/// @notice Token library for ERC-1155 calls.
library PositionTokens {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    function balanceOf(
        PoolsharkStructs.LimitImmutables memory constants,
        address owner,
        uint32 positionId
    ) internal view returns (uint256) {
        return
            IPositionERC1155(constants.poolToken).balanceOf(owner, positionId);
    }

    function name(address token0, address token1)
        internal
        view
        returns (bytes32 result)
    {
        string memory nameString = string.concat(
            'Poolshark ',
            ERC20(token0).symbol(),
            '-',
            ERC20(token1).symbol()
        );

        result = Bytes.from(nameString);
    }

    function symbol(address token0, address token1)
        internal
        view
        returns (bytes32 result)
    {
        string memory symbolString = string.concat(
            'PSHARK-',
            ERC20(token0).symbol(),
            '-',
            ERC20(token1).symbol()
        );

        result = Bytes.from(symbolString);
    }
}


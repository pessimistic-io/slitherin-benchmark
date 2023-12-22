// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

bytes4 constant SCA_EXECUTE = bytes4(
    keccak256("execute(address,uint256,bytes)")
);
bytes4 constant SCA_EXECUTE_OPTIMIZED = bytes4(
    keccak256("execute_ncC(address,uint256,bytes)")
);

function decodeExecuteCallOpCalldata(
    bytes calldata opCalldata,
    bool checkZeroCallValue
) pure returns (address dest, bytes4 selector, bytes calldata data) {
    bytes4 scaSelector = bytes4(opCalldata[0:4]); // bytes4

    if (scaSelector != SCA_EXECUTE && scaSelector != SCA_EXECUTE_OPTIMIZED) {
        revert("DecodeUtils: !selector");
    }

    // padded address (bytes4 selector + padding of 12 bytes) i.e. 4+12 = 16 to 16+20 = 36
    dest = address(bytes20(opCalldata[16:36]));

    // uint256 (bytes4 selector + padded address of 32 bytes) i.e. 4+32 = 36 to 36+32 = 68
    uint256 callValue = uint256(bytes32(opCalldata[36:68]));

    if (checkZeroCallValue && callValue > 0) {
        revert("DecodeUtils: !value");
    }

    // bytes (bytes4 selector + padded address of 32 bytes + uint256 of 32 bytes + offset of bytes32 + length of bytes32 + bytes4 of selector) i.e. 4+32+32+32+32 = 132 to 132+4 = 136
    selector = bytes4(opCalldata[132:136]);

    // bytes (bytes4 selector + padded address of 32 bytes + uint256 of 32 bytes + offset of bytes32 + length of bytes32 + bytes4 of selector) i.e. 4+32+32+32+32+4 = 136 to end
    data = opCalldata[136:];
}


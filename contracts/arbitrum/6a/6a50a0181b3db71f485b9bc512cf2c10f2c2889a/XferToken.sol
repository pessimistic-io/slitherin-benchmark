//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IArbAddressTable.sol";
import "./IERC20.sol";

contract XferToken {
    IERC20 public immutable token;
    IArbAddressTable public immutable addressRegistry;

    error TooShort();
    error TooLong();

    constructor(address _token, address _registry) {
        token = IERC20(_token);
        addressRegistry = IArbAddressTable(_registry);
    }

    fallback() external {
        if (msg.data.length < 3) {
            revert TooShort();
        }
        if (msg.data.length > 52) {
            revert TooLong();
        }

        address to;
        uint256 offset;
        if (msg.data.length < 21) {
            uint256 toId = uint24(bytes3(msg.data[:3]));
            to = addressRegistry.lookupIndex(toId);
            offset = 3;
        } else {
            to = address(bytes20(msg.data[:20]));
            offset = 20;
        }

        uint256 amountToShift = (offset + 32 - msg.data.length) * 8;
        uint256 value = uint256(bytes32(msg.data[offset:]) >> amountToShift);

        token.transferFrom(msg.sender, to, value);
    }
}


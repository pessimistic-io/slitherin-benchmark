// contracts/PNFTToken.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.7.6;
pragma abicoder v2;
import "./PNFTToken.sol";

/**
 * @title MockPNFTToken
 * WARNING: use only for testing and debugging purpose
 */
contract TestPNFTToken is PNFTToken {
    uint256 mockTime = 0;

    // constructor(string memory name, string memory symbol) PNFTToken(name, symbol) {}

    function setCurrentTime(uint256 _time) external {
        mockTime = _time;
    }

    function getCurrentTime() internal view virtual override returns (uint256) {
        return mockTime;
    }
}

